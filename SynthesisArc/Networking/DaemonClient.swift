import Foundation

/// HTTP client for agent-hooks daemon at :7899
///
/// Routes match the daemon's axum router in agent-hooks-peers/src/http.rs.
/// NOTE: Daemon currently binds to 127.0.0.1 — needs 0.0.0.0 for Tailscale access.
/// Tailscale IP for macbook: 100.111.226.82
actor DaemonClient {
    private let baseURL: URL
    private let session: URLSession

    init(host: String = "127.0.0.1", port: Int = 7899) {
        self.baseURL = URL(string: "http://\(host):\(port)")!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Registration

    /// Register this app as a peer in the daemon
    /// Returns the peer_id for subsequent operations
    func register(name: String = "daniel-ios", summary: String = "iOS Fleet App") async throws -> String {
        let body: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "cwd": "/",
            "name": name,
            "summary": summary
        ]
        let data = try await post("/register", body: body)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? String {
            return id
        }
        throw DaemonError.decodingError("Failed to parse register response")
    }

    /// Boot this app as a peer — register + join channels + get blackboard
    func boot(name: String = "daniel-ios", channels: [String] = ["engineering", "ops"], summary: String = "iOS Fleet App") async throws -> BootResponse {
        let body: [String: Any] = [
            "agent_id": name,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "cwd": "/",
            "summary": summary,
            "boot_channels": channels,
            "history_depth": 20
        ]
        let data = try await post("/boot", body: body)
        return try JSONDecoder().decode(BootResponse.self, from: data)
    }

    // MARK: - Peers (GET /list-peers)

    func listPeers(scope: String = "machine") async throws -> [Peer] {
        let data = try await get("/list-peers?scope=\(scope)")
        return try JSONDecoder().decode([Peer].self, from: data)
    }

    // MARK: - Channels

    /// GET /channels/list
    func listChannels() async throws -> [Channel] {
        let data = try await get("/channels/list")
        return try JSONDecoder().decode([Channel].self, from: data)
    }

    /// GET /channels/history?channel_name=X&limit=N
    func channelHistory(name: String, limit: Int = 50) async throws -> PaginatedChannelHistory {
        let data = try await get("/channels/history?channel_name=\(name.urlEncoded)&limit=\(limit)")
        return try JSONDecoder().decode(PaginatedChannelHistory.self, from: data)
    }

    /// POST /channels/send
    func sendChannelMessage(channel: String, fromId: String, content: String) async throws {
        let body: [String: Any] = [
            "channel_name": channel,
            "from_id": fromId,
            "content": content,
            "message_type": "text"
        ]
        _ = try await post("/channels/send", body: body)
    }

    // MARK: - Blackboard

    /// GET /blackboard/list (optional prefix filter)
    func listBlackboard(prefix: String? = nil) async throws -> [BlackboardEntry] {
        var path = "/blackboard/list"
        if let prefix { path += "?prefix=\(prefix.urlEncoded)" }
        let data = try await get(path)
        return try JSONDecoder().decode([BlackboardEntry].self, from: data)
    }

    /// POST /blackboard/set
    func setBlackboard(key: String, value: String, setBy: String) async throws {
        let body: [String: Any] = ["key": key, "value": value, "set_by": setBy]
        _ = try await post("/blackboard/set", body: body)
    }

    /// GET /blackboard/get?key=X
    func getBlackboard(key: String) async throws -> BlackboardEntry? {
        let data = try await get("/blackboard/get?key=\(key.urlEncoded)")
        let value = try JSONDecoder().decode(OptionalBlackboardEntry.self, from: data)
        return value.entry
    }

    // MARK: - DMs

    /// POST /send-message
    func sendDM(fromId: String, toName: String, content: String) async throws {
        let body: [String: Any] = [
            "from_id": fromId,
            "to_name": toName,
            "content": content,
            "message_type": "text"
        ]
        _ = try await post("/send-message", body: body)
    }

    /// GET /poll-messages?peer_id=X&mark_delivered=false
    func pollMessages(peerId: String, markDelivered: Bool = false) async throws -> [PeerDM] {
        let data = try await get("/poll-messages?peer_id=\(peerId)&mark_delivered=\(markDelivered)")
        return try JSONDecoder().decode([PeerDM].self, from: data)
    }

    // MARK: - SSE (Server-Sent Events)

    /// Connect to SSE stream at GET /events?peer_id=X
    /// Returns an AsyncStream of SseNotification
    func sseStream(peerId: String) -> AsyncStream<SseNotification> {
        AsyncStream { continuation in
            let url = baseURL.appending(path: "/events").appending(queryItems: [
                URLQueryItem(name: "peer_id", value: peerId)
            ])
            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            let _ = session.dataTask(with: request)
            // SSE parsing handled by the caller via URLSession delegate
            // For Phase 1, we use polling; SSE integration in Phase 2
            continuation.finish()
        }
    }

    // MARK: - Health

    /// GET /health
    func health() async throws -> Bool {
        let data = try await get("/health")
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String {
            return status == "ok"
        }
        return false
    }

    // MARK: - HTTP Primitives

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL.absoluteString)\(path)") else {
            throw DaemonError.invalidURL(path)
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DaemonError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL.absoluteString)\(path)") else {
            throw DaemonError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DaemonError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        return data
    }
}

// MARK: - Error Types

enum DaemonError: Error, LocalizedError {
    case httpError(Int)
    case invalidURL(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .invalidURL(let path): return "Invalid URL: \(path)"
        case .decodingError(let msg): return "Decode: \(msg)"
        }
    }
}

// MARK: - Additional Codable Types

/// DM message (matches Rust PeerMessage)
struct PeerDM: Codable, Identifiable {
    let id: Int64
    let fromId: String
    let toId: String
    let content: String
    let messageType: String?
    let replyTo: Int64?
    let sentAt: String
    let delivered: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fromId = "from_id"
        case toId = "to_id"
        case content
        case messageType = "message_type"
        case replyTo = "reply_to"
        case sentAt = "sent_at"
        case delivered
    }
}

/// Wrapper for nullable blackboard get response
private struct OptionalBlackboardEntry: Codable {
    let entry: BlackboardEntry?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        entry = try? container.decode(BlackboardEntry.self)
    }
}

// MARK: - URL Encoding Helper

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
