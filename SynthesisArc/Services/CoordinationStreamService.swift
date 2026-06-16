import Foundation

/// Real-time coordination events via forge-graphd SSE.
///
/// Connects to `GET /api/v1/events/coordination` and dispatches
/// peer_message, channel_message, and blackboard_update events.
@MainActor
final class CoordinationStreamService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var unreadCount = 0
    @Published private(set) var lastError: String?

    weak var fleetService: FleetService?
    weak var channelService: ChannelService?
    weak var dmService: DMService?

    private var streamTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private let bootChannels = ["engineering", "ops"]

    func start() {
        stop()
        streamTask = Task { [weak self] in
            await self?.runWithReconnect()
        }
        heartbeatTask = Task { [weak self] in
            await self?.runHeartbeat()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        isConnected = false
        fleetService?.setStreamConnected(false)
    }

    func markInboxRead() {
        unreadCount = 0
    }

    func seedInbox(_ messages: [CoordMessage]) {
        let resolver = PeerNameResolver.shared
        let enriched = messages.map { resolver.enrich($0) }
        dmService?.seedInbound(enriched)
    }

    // MARK: - Reconnect loop

    private func runWithReconnect() async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            let config = AppConfig.shared
            guard !config.apiKey.isEmpty else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }

            do {
                try await consumeStream()
                backoff = 1
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
                isConnected = false
                fleetService?.setStreamConnected(false)
                print("[CoordinationStream] disconnected: \(error)")
            }

            guard !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            backoff = min(backoff * 2, 30)
        }
    }

    private func consumeStream() async throws {
        let config = AppConfig.shared
        var components = URLComponents()
        components.scheme = "http"
        components.host = config.graphdHost
        components.port = config.graphdPort
        components.path = "/api/v1/events/coordination"
        components.queryItems = [
            URLQueryItem(name: "channels", value: bootChannels.joined(separator: ","))
        ]

        guard let url = components.url else {
            throw ForgeGraphError.invalidURL("/api/v1/events/coordination")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("ApiKey \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.agentName, forHTTPHeaderField: "X-Agent-Id")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 86400
        sessionConfig.timeoutIntervalForResource = 86400
        let session = URLSession(configuration: sessionConfig)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ForgeGraphError.httpError(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ForgeGraphError.httpError(http.statusCode)
        }

        isConnected = true
        lastError = nil
        fleetService?.setStreamConnected(true)
        print("[CoordinationStream] connected")

        var eventName: String?
        var dataBuffer: [String] = []

        for try await line in bytes.lines {
            try Task.checkCancellation()

            if line.isEmpty {
                if let payload = dataBuffer.joined(separator: "\n").nilIfEmpty {
                    await dispatchFrame(eventName: eventName, data: payload)
                }
                eventName = nil
                dataBuffer = []
                continue
            }

            if line.hasPrefix(":") { continue }

            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                dataBuffer.append(value)
            }
        }

        isConnected = false
        fleetService?.setStreamConnected(false)
    }

    private func dispatchFrame(eventName: String?, data: String) async {
        guard let jsonData = data.data(using: .utf8) else { return }
        guard let event = try? JSONDecoder().decode(CoordSseEvent.self, from: jsonData) else {
            print("[CoordinationStream] decode failed: \(data.prefix(120))")
            return
        }

        switch eventName ?? event.type {
        case "peer_message":
            guard let from = event.from,
                  let content = event.content,
                  let messageId = event.messageId,
                  let timestamp = event.timestamp else { return }
            let msg = CoordMessage.fromSSE(messageId: messageId, from: from, content: content, timestamp: timestamp)
            if dmService?.ingestInbound(msg) == true {
                unreadCount += 1
                let localAgent = AppConfig.shared.agentName
                if from != localAgent {
                    PushNotificationService.shared.notifyDM(from: from, content: content)
                }
            }

        case "channel_message":
            guard let channel = event.channel,
                  let from = event.from,
                  let content = event.content,
                  let messageId = event.messageId,
                  let timestamp = event.timestamp else { return }
            let msg = CoordMessage.fromSSEChannel(
                messageId: messageId,
                from: from,
                content: content,
                timestamp: timestamp
            )
            channelService?.appendLiveMessage(channel: channel, message: msg)

            let localAgent = AppConfig.shared.agentName
            guard from != localAgent else { break }

            if PushNotificationService.containsMention(of: localAgent, in: content) {
                PushNotificationService.shared.notifyMention(
                    channel: channel,
                    from: from,
                    content: content
                )
            } else if PushNotificationService.isWatchlistChannel(channel) {
                PushNotificationService.shared.notifyChannel(
                    channel: channel,
                    from: from,
                    preview: content
                )
            }

        case "blackboard_update":
            guard let key = event.key else { return }
            fleetService?.applyBlackboardUpdate(
                key: key,
                value: event.value,
                setBy: event.setBy,
                timestamp: event.timestamp
            )

            if PushNotificationService.isDegradedBlackboardUpdate(key: key, value: event.value) {
                let agent = String(key.dropLast(".status".count))
                PushNotificationService.shared.notifyDegraded(
                    agent: agent,
                    value: event.value ?? "degraded"
                )
            }

        default:
            break
        }
    }

    private func runHeartbeat() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard isConnected, !Task.isCancelled else { continue }
            let client = AppConfig.shared.makeClient()
            try? await client.heartbeat()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}