import Foundation

/// Per-peer DM storage — inbound inbox + bilateral thread cache (incl. optimistic outbound).
@MainActor
final class DMService: ObservableObject {
    @Published private(set) var inboundMessages: [CoordMessage] = []
    @Published private(set) var outboundMessages: [CoordMessage] = []
    /// Bilateral thread currently on screen — flat array for reliable SwiftUI refresh.
    @Published private(set) var activeThreadMessages: [CoordMessage] = []

    private var activePeerAgentName: String?
    private var pollTask: Task<Void, Never>?

    private var localAgentName: String {
        AppConfig.shared.agentName
    }

    // MARK: - Ingest

    /// Record an inbound DM (SSE peer_message or REST poll to local agent).
    @discardableResult
    func ingestInbound(_ message: CoordMessage) -> Bool {
        guard !inboundMessages.contains(where: { $0.id == message.id }) else { return false }
        var updated = inboundMessages
        updated.append(message)
        updated.sort { $0.sentAtUnixMs > $1.sentAtUnixMs }
        inboundMessages = updated
        refreshActiveThread()
        return true
    }

    /// Seed inbound messages from REST poll / boot pending DMs.
    func seedInbound(_ messages: [CoordMessage]) {
        for message in messages {
            ingestInbound(message)
        }
        reconcileOutbound(with: messages)
        refreshActiveThread()
    }

    func setActivePeer(_ peerAgentName: String?) {
        if activePeerAgentName != peerAgentName {
            stopPolling()
        }
        activePeerAgentName = peerAgentName
        refreshActiveThread()
        if peerAgentName != nil {
            startPolling(interval: 10)
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// REST poll fallback for agent responses when SSE is slow or disconnected.
    func startPolling(interval: TimeInterval = 10) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { break }
                await self.pollInbox()
            }
        }
    }

    func pollInbox() async {
        let client = AppConfig.shared.makeClient()
        guard !AppConfig.shared.apiKey.isEmpty else { return }
        do {
            let polled = try await client.pollMessages()
            let resolver = PeerNameResolver.shared
            seedInbound(polled.map { resolver.enrich($0) })
        } catch {
            print("[DMService] pollInbox failed: \(error)")
        }
    }

    /// Append optimistic outbound DM to the bilateral thread cache.
    func appendOutbound(_ message: CoordMessage) {
        guard message.fromAgentName == localAgentName,
              message.toAgentName != nil else { return }
        var updated = outboundMessages
        updated.append(message)
        updated.sort { $0.sentAtUnixMs < $1.sentAtUnixMs }
        outboundMessages = updated
        refreshActiveThread()
    }

    // MARK: - Queries

    /// Inbound messages from a single sender (inbox grouping).
    func messages(from sender: String) -> [CoordMessage] {
        inboundMessages
            .filter { senderAgentName(for: $0) == sender }
            .sorted { $0.sentAtUnixMs > $1.sentAtUnixMs }
    }

    /// Bilateral thread between local agent and `peerAgentName` (both directions).
    func messages(with peerAgentName: String) -> [CoordMessage] {
        let inbound = inboundMessages.filter { senderAgentName(for: $0) == peerAgentName }
        let outbound = outboundMessages.filter { $0.toAgentName == peerAgentName }
        return (inbound + outbound).sorted { $0.sentAtUnixMs < $1.sentAtUnixMs }
    }

    /// Slack-style inbox sidebar: one row per sender, newest first.
    func conversationSummaries() -> [DMConversationSummary] {
        let grouped = Dictionary(grouping: inboundMessages) { senderAgentName(for: $0) }
        return grouped
            .compactMap { sender, msgs -> DMConversationSummary? in
                guard !sender.isEmpty, sender != "unknown" else { return nil }
                guard let latest = msgs.max(by: { $0.sentAtUnixMs < $1.sentAtUnixMs }) else { return nil }
                return DMConversationSummary(
                    senderAgentName: sender,
                    latestMessage: latest,
                    messageCount: msgs.count
                )
            }
            .sorted { $0.latestMessage.sentAtUnixMs > $1.latestMessage.sentAtUnixMs }
    }

    // MARK: - Send helper

    func makeOptimisticOutbound(to peerAgentName: String, content: String) -> CoordMessage {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return CoordMessage(
            id: UInt64(bitPattern: Int64(nowMs)),
            from: nil,
            channel: nil,
            dmTo: nil,
            content: content,
            messageType: .text,
            replyTo: nil,
            sentAtUnixMs: nowMs,
            pinned: false,
            fromAgentName: localAgentName,
            toAgentName: peerAgentName
        )
    }

    // MARK: - Private

    private func senderAgentName(for message: CoordMessage) -> String {
        if let name = message.fromAgentName, !name.isEmpty {
            return name
        }
        if let from = message.from {
            return String(from)
        }
        return "unknown"
    }

    /// Drop optimistic outbound rows once the server echoes the same content back.
    private func reconcileOutbound(with serverMessages: [CoordMessage]) {
        guard !outboundMessages.isEmpty else { return }
        let local = localAgentName
        var updated = outboundMessages
        updated.removeAll { optimistic in
            guard optimistic.fromAgentName == local,
                  let to = optimistic.toAgentName else { return false }
            return serverMessages.contains { server in
                server.content == optimistic.content
                    && senderAgentName(for: server) == local
                    && (server.toAgentName == to || server.dmTo != nil)
            }
        }
        outboundMessages = updated
        refreshActiveThread()
    }

    private func refreshActiveThread() {
        guard let peer = activePeerAgentName else {
            activeThreadMessages = []
            return
        }
        activeThreadMessages = messages(with: peer)
    }
}

struct DMConversationSummary: Identifiable {
    var id: String { senderAgentName }
    let senderAgentName: String
    let latestMessage: CoordMessage
    let messageCount: Int
}