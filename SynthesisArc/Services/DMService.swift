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
    private var hydrateTask: Task<Void, Never>?
    private var deliveredMessageIds: Set<UInt64> = []
    private static let recentPeersKey = "dm.recentPeers"

    private var localAgentName: String {
        AppConfig.shared.agentName
    }

    init() {
        let stored = DMThreadPersistence.load(for: localAgentName)
        inboundMessages = stored.inbound
        outboundMessages = stored.outbound
    }

    // MARK: - Ingest

    /// Record an inbound DM (SSE peer_message or REST poll to local agent).
    @discardableResult
    func ingestInbound(_ message: CoordMessage) -> Bool {
        let message = PeerNameResolver.shared.enrich(message, rosterAgents: rosterAgentNames())
        if let index = inboundMessages.firstIndex(where: { $0.id == message.id }) {
            let merged = mergePreservingContent(existing: inboundMessages[index], incoming: message)
            guard !messagesEquivalent(merged, inboundMessages[index]) else { return false }
            var updated = inboundMessages
            updated[index] = merged
            inboundMessages = updated
            refreshActiveThread()
            persistThreads()
            return true
        }
        var updated = inboundMessages
        updated.append(message)
        updated.sort { $0.sentAtUnixMs > $1.sentAtUnixMs }
        inboundMessages = updated
        refreshActiveThread()
        persistThreads()
        return true
    }

    /// Seed inbound messages from REST poll / boot pending DMs.
    func seedInbound(_ messages: [CoordMessage]) {
        let roster = rosterAgentNames()
        let enriched = PeerNameResolver.shared.enrichMessageBatch(messages, rosterAgents: roster)
        for message in enriched {
            ingestInbound(message)
        }
        refreshActiveThread()
        Task { await hydrateAllEmptyMessages() }
    }

    private func rosterAgentNames() -> [String] {
        var names = Set(PeerNameResolver.shared.nameMap.keys)
        for message in inboundMessages + outboundMessages {
            if let from = message.fromAgentName { names.insert(from) }
            if let to = message.toAgentName { names.insert(to) }
        }
        names.remove(localAgentName)
        return names.sorted()
    }

    func setActivePeer(_ peerAgentName: String?) {
        if activePeerAgentName != peerAgentName {
            stopPolling()
            hydrateTask?.cancel()
            hydrateTask = nil
        }
        activePeerAgentName = peerAgentName
        refreshActiveThread()
        if let peer = peerAgentName {
            recordRecentPeer(peer)
            startPolling(interval: 10)
            hydrateTask = Task { [weak self] in
                await self?.hydrateThreadContent(for: peer)
            }
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
              let peer = message.toAgentName else { return }
        var updated = outboundMessages
        updated.append(message)
        updated.sort { $0.sentAtUnixMs < $1.sentAtUnixMs }
        outboundMessages = updated
        recordRecentPeer(peer)
        refreshActiveThread()
        persistThreads()
    }

    /// Replace optimistic id with the server-assigned message node id after send succeeds.
    func confirmOutbound(optimisticId: NodeId, serverId: NodeId, to peerAgentName: String, content: String) {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UsabilityTrace.shared.recordIssue(
                signature: "dm.content.empty",
                message: "Outbound DM confirmed with empty body",
                severity: .warn,
                context: ["peer": peerAgentName, "message_id": String(serverId)]
            )
        }
        var updated = outboundMessages
        if let index = updated.firstIndex(where: { $0.id == optimisticId }) {
            updated[index] = updated[index].with(id: serverId, content: content)
        } else if let index = updated.firstIndex(where: {
            $0.toAgentName == peerAgentName && $0.content == content
        }) {
            updated[index] = updated[index].with(id: serverId)
        } else {
            updated.append(
                makeOptimisticOutbound(to: peerAgentName, content: content).with(id: serverId)
            )
        }
        updated.sort { $0.sentAtUnixMs < $1.sentAtUnixMs }
        outboundMessages = updated
        recordRecentPeer(peerAgentName)
        refreshActiveThread()
        persistThreads()
    }

    /// Record a confirmed outbound DM from SSE (sender is the local agent).
    func ingestOutboundEcho(_ message: CoordMessage, to peerAgentName: String) {
        var normalized = message.with(
            fromAgentName: localAgentName,
            toAgentName: peerAgentName
        )
        if let index = outboundMessages.firstIndex(where: { $0.id == normalized.id }) {
            var updated = outboundMessages
            if !normalized.hasDisplayableContent, updated[index].hasDisplayableContent {
                normalized = normalized.with(content: updated[index].content)
            }
            updated[index] = normalized
            outboundMessages = updated
        } else if let index = outboundMessages.firstIndex(where: {
            $0.toAgentName == peerAgentName
                && !$0.content.isEmpty
                && ($0.content == normalized.content || normalized.content.isEmpty)
        }) {
            var updated = outboundMessages
            updated[index] = updated[index].with(
                id: normalized.id,
                content: normalized.hasDisplayableContent ? normalized.content : updated[index].content
            )
            outboundMessages = updated
        } else {
            appendOutbound(normalized)
            return
        }
        refreshActiveThread()
        persistThreads()
    }

    /// Bump peer to front of recents (survives relaunch; used for outbound-only threads).
    func recordRecentPeer(_ agentName: String) {
        let trimmed = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != localAgentName else { return }
        var recents = loadRecentPeerTouches()
        recents.removeAll { $0 == trimmed }
        recents.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(16)), forKey: Self.recentPeersKey)
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

    /// Unread inbound messages not yet opened in a thread.
    var unreadInboundCount: Int {
        inboundMessages.filter { !deliveredMessageIds.contains($0.id) }.count
    }

    /// Per-sender unread for inbox list row badges.
    func unreadCount(from sender: String) -> Int {
        messages(from: sender).filter { !deliveredMessageIds.contains($0.id) }.count
    }

    /// Mark server-side delivery and local read state for a sender's inbox thread.
    func markConversationDelivered(sender: String) async {
        let ids = messages(from: sender).map(\.id)
        guard !ids.isEmpty else { return }
        deliveredMessageIds.formUnion(ids)
        let client = AppConfig.shared.makeClient()
        guard !AppConfig.shared.apiKey.isEmpty else { return }
        do {
            try await client.markDelivered(ids: ids)
        } catch {
            print("[DMService] markDelivered failed: \(error)")
        }
    }

    /// Bilateral recents — inbound and outbound DMs, newest activity first.
    func recentConversationSummaries(maxCount: Int = 12) -> [RecentConversationSummary] {
        var byPeer: [String: [CoordMessage]] = [:]

        for message in inboundMessages {
            let peer = resolvedPeerAgentName(for: message)
            guard !peer.isEmpty, peer != "unknown", peer != localAgentName else { continue }
            byPeer[peer, default: []].append(message)
        }
        for message in outboundMessages {
            guard let peer = message.toAgentName, peer != localAgentName else { continue }
            byPeer[peer, default: []].append(message)
        }

        var summaries: [RecentConversationSummary] = byPeer.compactMap { peer, messages in
            guard let latest = bestPreviewMessage(from: messages) else { return nil }
            let outbound = latest.fromAgentName == localAgentName || latest.toAgentName != nil
            return RecentConversationSummary(
                peerAgentName: peer,
                latestMessage: latest,
                messageCount: messages.count,
                lastMessageIsOutbound: outbound
            )
        }

        let touched = loadRecentPeerTouches()
        for peer in touched where !summaries.contains(where: { $0.peerAgentName == peer }) {
            summaries.append(
                RecentConversationSummary(
                    peerAgentName: peer,
                    latestMessage: placeholderMessage(to: peer),
                    messageCount: 0,
                    lastMessageIsOutbound: true
                )
            )
        }

        summaries.sort {
            recencyScore($0, touched: touched) > recencyScore($1, touched: touched)
        }

        return Array(summaries.prefix(maxCount))
    }

    /// Unified bilateral inbox — one row per peer agent (inbound + outbound), newest first.
    func unifiedConversations(maxCount: Int = 50) -> [RecentConversationSummary] {
        recentConversationSummaries(maxCount: maxCount)
    }

    /// Legacy inbound-only grouping — prefer `unifiedConversations()`.
    func conversationSummaries() -> [DMConversationSummary] {
        let grouped = Dictionary(grouping: inboundMessages) { resolvedPeerAgentName(for: $0) }
        return grouped
            .compactMap { sender, msgs -> DMConversationSummary? in
                guard isValidPeer(sender) else { return nil }
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

    /// Backfill empty bodies across every conversation (inbox preview + threads).
    func hydrateAllEmptyMessages() async {
        let peers = Set(
            inboundMessages.compactMap { resolvedPeerAgentName(for: $0) }
            + outboundMessages.compactMap(\.toAgentName)
        ).filter { isValidPeer($0) }
        for peer in peers {
            guard !Task.isCancelled else { return }
            await hydrateThreadContent(for: peer)
        }
    }

    /// Backfill empty message bodies from graph node properties.
    func hydrateThreadContent(for peerAgentName: String) async {
        let targets = messages(with: peerAgentName).filter { !$0.hasReadableBody && $0.id > 0 }
        guard !targets.isEmpty else { return }

        let client = AppConfig.shared.makeClient()
        guard !AppConfig.shared.apiKey.isEmpty else { return }

        for message in targets {
            guard !Task.isCancelled else { return }
            do {
                guard let content = try await client.fetchNodeContent(id: message.id),
                      content.isEmpty == false else { continue }
                applyHydratedContent(content, to: message.id)
            } catch {
                print("[DMService] hydrate \(message.id) failed: \(error)")
            }
        }
        let stillEmpty = messages(with: peerAgentName).contains {
            !$0.hasDisplayableContent && $0.id > 0
        }
        if stillEmpty {
            UsabilityTrace.shared.recordIssue(
                signature: "dm.content.empty",
                message: "DM thread has messages with empty body after hydration",
                severity: .warn,
                context: ["peer": peerAgentName]
            )
        }
    }

    // MARK: - Private

    private func isValidPeer(_ peer: String) -> Bool {
        !peer.isEmpty && peer != "unknown" && peer != localAgentName
    }

    private func senderAgentName(for message: CoordMessage) -> String {
        resolvedPeerAgentName(for: message)
    }

    /// Resolve inbound sender to a stable agent name (never a raw session id when avoidable).
    private func resolvedPeerAgentName(for message: CoordMessage) -> String {
        let enriched = PeerNameResolver.shared.enrich(message)
        if let name = enriched.fromAgentName, !name.isEmpty, isValidPeer(name) {
            if name.contains("-") || !name.allSatisfy(\.isNumber) {
                return name
            }
        }
        if let from = enriched.from,
           let agent = PeerNameResolver.shared.agentName(forSession: from),
           isValidPeer(agent) {
            return agent
        }
        if let name = enriched.fromAgentName, !name.isEmpty {
            return name
        }
        if let from = enriched.from {
            return String(from)
        }
        return "unknown"
    }

    private func bestPreviewMessage(from messages: [CoordMessage]) -> CoordMessage? {
        let sorted = messages.sorted { $0.sentAtUnixMs > $1.sentAtUnixMs }
        if let readable = sorted.first(where: { $0.hasReadableBody }) {
            return readable
        }
        if let anyContent = sorted.first(where: { $0.hasDisplayableContent }) {
            return anyContent
        }
        return sorted.first
    }

    private func messagesEquivalent(_ lhs: CoordMessage, _ rhs: CoordMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.content == rhs.content
            && lhs.fromAgentName == rhs.fromAgentName
            && lhs.toAgentName == rhs.toAgentName
            && lhs.sentAtUnixMs == rhs.sentAtUnixMs
    }

    private func mergePreservingContent(existing: CoordMessage, incoming: CoordMessage) -> CoordMessage {
        var merged = incoming
        if !incoming.hasReadableBody, existing.hasReadableBody {
            merged = merged.with(content: existing.content)
        } else if incoming.readableBody.isEmpty, !existing.readableBody.isEmpty {
            merged = merged.with(content: existing.content)
        }
        if merged.fromAgentName == nil, let from = existing.fromAgentName {
            merged = merged.with(fromAgentName: from)
        }
        if merged.toAgentName == nil, let to = existing.toAgentName {
            merged = merged.with(toAgentName: to)
        }
        return merged
    }

    private func applyHydratedContent(_ content: String, to messageId: NodeId) {
        var changed = false
        if let index = inboundMessages.firstIndex(where: { $0.id == messageId }) {
            var updated = inboundMessages
            updated[index] = updated[index].with(content: content)
            inboundMessages = updated
            changed = true
        }
        if let index = outboundMessages.firstIndex(where: { $0.id == messageId }) {
            var updated = outboundMessages
            updated[index] = updated[index].with(content: content)
            outboundMessages = updated
            changed = true
        }
        guard changed else { return }
        refreshActiveThread()
        persistThreads()
    }

    private func refreshActiveThread() {
        guard let peer = activePeerAgentName else {
            activeThreadMessages = []
            return
        }
        activeThreadMessages = messages(with: peer)
    }

    private func persistThreads() {
        DMThreadPersistence.save(
            agentName: localAgentName,
            inbound: inboundMessages,
            outbound: outboundMessages
        )
    }

    private func loadRecentPeerTouches() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentPeersKey) ?? []
    }

    private func recencyScore(_ summary: RecentConversationSummary, touched: [String]) -> Int64 {
        if summary.messageCount > 0 {
            return summary.latestMessage.sentAtUnixMs
        }
        guard let index = touched.firstIndex(of: summary.peerAgentName) else { return 0 }
        let anchorMs = Int64(Date().timeIntervalSince1970 * 1000)
        return anchorMs - Int64(index)
    }

    private func placeholderMessage(to peer: String) -> CoordMessage {
        CoordMessage(
            id: 0,
            from: nil,
            channel: nil,
            dmTo: nil,
            content: "No messages yet",
            messageType: .text,
            replyTo: nil,
            sentAtUnixMs: 0,
            pinned: false,
            fromAgentName: localAgentName,
            toAgentName: peer
        )
    }
}

struct DMConversationSummary: Identifiable {
    var id: String { senderAgentName }
    let senderAgentName: String
    let latestMessage: CoordMessage
    let messageCount: Int
}

struct RecentConversationSummary: Identifiable {
    var id: String { peerAgentName }
    let peerAgentName: String
    let latestMessage: CoordMessage
    let messageCount: Int
    let lastMessageIsOutbound: Bool
}