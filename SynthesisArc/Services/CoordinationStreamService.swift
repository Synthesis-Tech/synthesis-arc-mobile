import Foundation

/// Real-time coordination events via forge-graphd SSE.
///
/// Connects to `GET /api/v1/events/coordination` and dispatches
/// peer_message, channel_message, and blackboard_update events.
@MainActor
final class CoordinationStreamService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var unreadCount = 0
    @Published private(set) var lastError: String?

    weak var fleetService: FleetService?
    weak var channelService: ChannelService?
    weak var dmService: DMService?

    private var streamTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    /// True while a reconnect loop is running but bytes are not yet flowing.
    var isPendingConnection: Bool {
        streamTask != nil && !isConnected
    }

    /// Start (or restart) the SSE reconnect loop and heartbeat.
    func start(force: Bool = false) {
        if !force {
            if isConnected {
                CoordinationAuditLog.shared.log("SSE start skipped — already connected", category: .sse)
                return
            }
            if streamTask != nil {
                CoordinationAuditLog.shared.log(
                    "SSE start skipped — handshake already in progress",
                    category: .sse
                )
                return
            }
        } else {
            CoordinationAuditLog.shared.log("SSE force restart requested", category: .sse)
            stop()
        }
        CoordinationAuditLog.shared.log("SSE start requested", category: .sse)
        beginStreaming()
    }

    /// Resume only when disconnected — avoids tearing down a live stream on foreground.
    func resumeIfNeeded() {
        guard !isConnected else {
            CoordinationAuditLog.shared.log("SSE resume skipped — already live", category: .sse)
            return
        }
        guard streamTask == nil else {
            CoordinationAuditLog.shared.log("SSE resume skipped — reconnect loop active", category: .sse)
            return
        }
        CoordinationAuditLog.shared.log("SSE resume requested", category: .sse)
        beginStreaming()
    }

    /// Human-readable SSE state for diagnostics and connection tests.
    var connectionStatusLabel: String {
        if isConnected { return "SSE + REST live" }
        if isPendingConnection { return "REST live · SSE connecting" }
        if lastError != nil { return "REST live · SSE unavailable" }
        return "REST live · SSE optional"
    }

    /// Wait until SSE connects or the timeout elapses.
    func waitForConnection(timeout: TimeInterval = 30) async -> Bool {
        let steps = max(1, Int(timeout * 10))
        for _ in 0..<steps where !isConnected {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isConnected
    }

    private func beginStreaming() {
        streamTask = Task { [weak self] in
            await self?.runWithReconnect()
        }
        if heartbeatTask == nil {
            heartbeatTask = Task { [weak self] in
                await self?.runHeartbeat()
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        isConnected = false
        isConnecting = false
        fleetService?.setStreamConnected(false)
    }

    func markInboxRead() {
        unreadCount = 0
    }

    func reduceUnread(by count: Int) {
        unreadCount = max(0, unreadCount - count)
    }

    func seedInbox(_ messages: [CoordMessage]) {
        let roster = Array(PeerNameResolver.shared.nameMap.keys).sorted()
        let enriched = PeerNameResolver.shared.enrichMessageBatch(
            messages,
            rosterAgents: roster
        )
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

            isConnecting = true
            lastError = nil
            let connectStarted = Date()
            do {
                try await consumeStream(connectStarted: connectStarted)
                backoff = 1
            } catch is CancellationError {
                isConnecting = false
                break
            } catch {
                lastError = Self.describeStreamError(error)
                isConnected = false
                isConnecting = false
                fleetService?.setStreamConnected(false)
                CoordinationAuditLog.shared.log(
                    "SSE disconnected: \(lastError ?? error.localizedDescription)",
                    category: .sse,
                    level: .warn
                )
                print("[CoordinationStream] disconnected: \(error)")
            }

            guard !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            backoff = min(backoff * 2, 30)
        }
    }

    private func consumeStream(connectStarted: Date) async throws {
        let client = AppConfig.shared.makeClient()
        CoordinationAuditLog.shared.log(
            "SSE handshake started → \(await client.graphdBaseURLString)/api/v1/events/coordination",
            category: .sse
        )

        let (bytes, response) = try await client.openCoordinationStream()
        guard let http = response as? HTTPURLResponse else {
            throw ForgeGraphError.httpError(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ForgeGraphError.httpError(http.statusCode)
        }

        isConnected = true
        isConnecting = false
        lastError = nil
        fleetService?.setStreamConnected(true)
        let config = AppConfig.shared
        let elapsed = Int(Date().timeIntervalSince(connectStarted) * 1000)
        CoordinationAuditLog.shared.log(
            "SSE connected to \(config.graphdHost):\(config.graphdPort) in \(elapsed)ms",
            category: .sse
        )
        if elapsed > 10_000 {
            CoordinationAuditLog.shared.log(
                "Slow SSE handshake — keep Tailscale MagicDNS hostname in Settings (not raw IP)",
                category: .sse,
                level: .warn
            )
        }
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
        isConnecting = false
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
            PeerNameResolver.shared.indexLiveMessage(id: messageId, fromAgent: from)
            let msg = CoordMessage.fromSSE(messageId: messageId, from: from, content: content, timestamp: timestamp)
            let localAgent = AppConfig.shared.agentName
            if from == localAgent, let peer = event.to {
                dmService?.ingestOutboundEcho(msg, to: peer)
            } else if dmService?.ingestInbound(msg) == true {
                unreadCount += 1
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
            PeerNameResolver.shared.indexLiveChannelMessage(id: messageId, fromAgent: from)
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
            } else if PushNotificationService.isTargetedReplyToOtherAgent(
                in: content,
                localAgent: localAgent
            ) {
                break
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

    private static func describeStreamError(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .appTransportSecurityRequiresSecureConnection {
            return """
            ATS blocked HTTP to graphd. Keep Host as Tailscale name (e.g. macbook-pro), not a 100.x IP. \
            REST and SSE must use the same hostname.
            """
        }
        return error.localizedDescription
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}