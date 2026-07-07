import Foundation

/// HTTP client for forge-graphd coordination API at :9090
///
/// Routes match `forge-graphd/src/peer_handlers.rs` and `sse_coordination.rs`.
/// Identity is carried via `X-Agent-Id` header (E2 invariant — never in body).
actor ForgeGraphClient {
    private let baseURL: URL
    private let apiKey: String
    private let agentId: String
    private let session: URLSession
    /// Long-lived SSE — same default ATS profile as REST, extended read timeouts only.
    private let streamSession: URLSession

    init(host: String, port: Int, apiKey: String, agentId: String) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        self.apiKey = apiKey
        self.agentId = agentId

        let restConfig = URLSessionConfiguration.default
        restConfig.timeoutIntervalForRequest = 15
        restConfig.timeoutIntervalForResource = 45
        self.session = URLSession(configuration: restConfig)

        let streamConfig = URLSessionConfiguration.default
        streamConfig.timeoutIntervalForRequest = 120
        streamConfig.timeoutIntervalForResource = 86_400
        self.streamSession = URLSession(configuration: streamConfig)
    }

    /// The exact graphd base URL used for REST — logged for SSE diagnostics.
    var graphdBaseURLString: String {
        baseURL.absoluteString
    }

    // MARK: - Boot

    func boot(
        channels: [String] = ["engineering", "ops"],
        summary: String = "Forge Commander"
    ) async throws -> BootResponse {
        let body: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "cwd": "/",
            "summary": summary,
            "boot_channels": channels
        ]
        let data = try await post("/api/v1/peers/boot", body: body)
        return try JSONDecoder().decode(BootResponse.self, from: data)
    }

    // MARK: - Peers

    func listPeers(scope: String = "all") async throws -> [Peer] {
        let data = try await get("/api/v1/peers/list?scope=\(scope)")
        return try JSONDecoder().decode([Peer].self, from: data)
    }

    func heartbeat() async throws {
        _ = try await post("/api/v1/peers/heartbeat", body: [:])
    }

    // MARK: - Channels

    func listChannels() async throws -> [Channel] {
        let data = try await get("/api/v1/channels/list")
        return try JSONDecoder().decode([Channel].self, from: data)
    }

    func createChannel(
        name: String,
        description: String? = nil,
        visibility: ChannelVisibility = .public
    ) async throws -> NodeId {
        var body: [String: Any] = ["name": name]
        if let description, !description.isEmpty {
            body["description"] = description
        }
        body["visibility"] = visibility == .private ? "private" : "public"
        let data = try await post("/api/v1/channels", body: body)
        struct CreateResponse: Decodable { let channel_id: UInt64 }
        return try JSONDecoder().decode(CreateResponse.self, from: data).channel_id
    }

    func joinChannel(name: String) async throws {
        _ = try await post("/api/v1/channels/\(name.urlPathEncoded)/join", body: [:])
    }

    func channelHistory(name: String, limit: Int = 50) async throws -> [CoordMessage] {
        let path = "/api/v1/channels/\(name.urlPathEncoded)/history?limit=\(limit)"
        let data = try await get(path)
        return try JSONDecoder().decode([CoordMessage].self, from: data)
    }

    func sendChannelMessage(channel: String, content: String, replyTo: NodeId? = nil) async throws -> NodeId? {
        var body: [String: Any] = [
            "content": content,
            "message_type": "text"
        ]
        if let replyTo {
            body["reply_to"] = replyTo
        }
        let data = try await post("/api/v1/channels/\(channel.urlPathEncoded)/send", body: body)
        struct SendResponse: Decodable { let message_id: UInt64? }
        return try? JSONDecoder().decode(SendResponse.self, from: data).message_id
    }

    // MARK: - DMs

    func sendDM(to: String, content: String) async throws -> NodeId? {
        let body: [String: Any] = [
            "to": to,
            "content": content,
            "message_type": "text"
        ]
        let data = try await post("/api/v1/messages/send", body: body)
        struct SendResponse: Decodable { let message_id: UInt64? }
        return try JSONDecoder().decode(SendResponse.self, from: data).message_id
    }

    /// Fetch message body from graph node properties when poll/history omitted content.
    func fetchNodeContent(id: NodeId) async throws -> String? {
        let data = try await get("/api/v1/nodes/\(id)")
        return Self.extractNodeStringProperty(named: "content", from: data)
    }

    private static func extractNodeStringProperty(named key: String, from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let node = root["data"] as? [String: Any],
              let properties = node["properties"] as? [String: Any],
              let value = properties[key] else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let tagged = value as? [String: Any] {
            if let string = tagged["String"] as? String { return string }
            if let string = tagged["string"] as? String { return string }
        }
        return nil
    }

    func pollMessages() async throws -> [CoordMessage] {
        let data = try await get("/api/v1/messages/poll")
        return try JSONDecoder().decode([CoordMessage].self, from: data)
    }

    func markDelivered(ids: [NodeId]) async throws {
        let body: [String: Any] = [
            "agent_id": agentId,
            "ids": ids
        ]
        _ = try await post("/api/v1/messages/mark-delivered", body: body)
    }

    // MARK: - Blackboard

    func listBlackboard(prefix: String? = nil) async throws -> [BlackboardEntry] {
        var path = "/api/v1/blackboard"
        if let prefix {
            path += "?prefix=\(prefix.urlEncoded)"
        }
        let data = try await get(path)
        return try JSONDecoder().decode([BlackboardEntry].self, from: data)
    }

    func setBlackboard(key: String, value: String, ttlSeconds: Int64? = nil) async throws {
        var body: [String: Any] = ["value": value]
        if let ttlSeconds {
            body["ttl_seconds"] = ttlSeconds
        }
        _ = try await put("/api/v1/blackboard/\(key.urlPathEncoded)", body: body)
    }

    func getBlackboard(key: String) async throws -> BlackboardEntry? {
        let data = try await get("/api/v1/blackboard/\(key.urlPathEncoded)")
        return try? JSONDecoder().decode(BlackboardEntry.self, from: data)
    }

    // MARK: - SSE

    /// Open the coordination event stream using the same host/scheme as REST (ATS-safe on device).
    func openCoordinationStream() async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard apiKey.isEmpty == false else {
            throw ForgeGraphError.missingApiKey
        }
        guard let url = URL(string: "\(baseURL.absoluteString)/api/v1/events/coordination") else {
            throw ForgeGraphError.invalidURL("/api/v1/events/coordination")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(agentId, forHTTPHeaderField: "X-Agent-Id")

        return try await streamSession.bytes(for: request)
    }

    // MARK: - Health

    func health() async throws -> Bool {
        guard let url = URL(string: "\(baseURL.absoluteString)/health") else {
            throw ForgeGraphError.invalidURL("/health")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ForgeGraphError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let report = try JSONDecoder().decode(HealthReport.self, from: data)
        return report.isHealthy
    }

    // MARK: - HTTP Primitives

    private func get(_ path: String) async throws -> Data {
        try await request(path, method: "GET", body: nil)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        try await request(path, method: "POST", body: body)
    }

    private func put(_ path: String, body: [String: Any]) async throws -> Data {
        try await request(path, method: "PUT", body: body)
    }

    private func request(_ path: String, method: String, body: [String: Any]?) async throws -> Data {
        guard apiKey.isEmpty == false else {
            throw ForgeGraphError.missingApiKey
        }
        guard let url = URL(string: "\(baseURL.absoluteString)\(path)") else {
            throw ForgeGraphError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(agentId, forHTTPHeaderField: "X-Agent-Id")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ForgeGraphError.httpError(0)
        }

        guard (200...299).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(GraphdErrorEnvelope.self, from: data) {
                throw ForgeGraphError.apiError(http.statusCode, err.message)
            }
            throw ForgeGraphError.httpError(http.statusCode)
        }

        return data
    }
}

// MARK: - Errors

enum ForgeGraphError: Error, LocalizedError {
    case httpError(Int)
    case invalidURL(String)
    case apiError(Int, String)
    case missingApiKey
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .invalidURL(let path): return "Invalid URL: \(path)"
        case .apiError(let code, let msg): return "HTTP \(code): \(msg)"
        case .missingApiKey: return "API key required — configure in Settings"
        case .decodingError(let msg): return "Decode: \(msg)"
        }
    }

    var isForbidden: Bool {
        switch self {
        case .httpError(403), .apiError(403, _): return true
        default: return false
        }
    }
}

extension Error {
    var isForbiddenChannelAccess: Bool {
        (self as? ForgeGraphError)?.isForbidden == true
    }

    var isAlreadyChannelMember: Bool {
        guard let error = self as? ForgeGraphError else { return false }
        switch error {
        case .apiError(let code, let message):
            let lowered = message.lowercased()
            return code == 409
                || lowered.contains("already a member")
                || lowered.contains("already joined")
                || lowered.contains("already in")
        default:
            return false
        }
    }
}

private struct GraphdErrorEnvelope: Codable {
    let error: String
    let message: String
}

// MARK: - URL Encoding

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    var urlPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
