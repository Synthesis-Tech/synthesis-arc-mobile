import Foundation
import Combine

/// Coordinates channel data from forge-graphd
@MainActor
class ChannelService: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var messages: [String: [CoordMessage]] = [:]
    /// Messages for the channel thread currently on screen — flat array so SwiftUI reliably refreshes.
    @Published private(set) var activeMessages: [CoordMessage] = []
    @Published var channelUnread: [String: Int] = [:]
    @Published var channelPreviews: [String: ChannelPreview] = [:]
    @Published var isLoading = false
    @Published var error: String?
    @Published var activeThreadError: String?
    /// Visibility for channels created this session before list refresh propagates.
    @Published private(set) var createdChannelVisibility: [String: ChannelVisibility] = [:]
    /// Private channels where history returned 403 — caller must join explicitly.
    @Published private(set) var privateAccessDenied: Set<String> = []
    /// Private channels confirmed non-member after server probe — show join gate.
    @Published private(set) var needsJoin: Set<String> = []
    /// Channels this principal has joined or successfully read as a member.
    @Published private(set) var joinedChannels: Set<String> = []

    private var client: ForgeGraphClient
    private static let joinedChannelsDefaultsPrefix = "channel.joined.names"
    private var activeChannelName: String?
    private var historyRefreshTask: Task<Void, Never>?
    /// Channels with an in-flight history fetch — late callers spin-yield instead of nested MainActor tasks (deadlock-safe).
    private var loadingHistoryChannels: Set<String> = []
    /// Prevents a cancelled/stale load from applying after a newer load started.
    private var inflightHistoryTaskIds: [String: UUID] = [:]
    private static let historyFetchTimeoutSeconds: TimeInterval = 15
    private var lastMembershipSyncAt: Date?
    private let membershipSyncCooldown: TimeInterval = 45

    var totalChannelUnread: Int {
        channelUnread.values.reduce(0, +)
    }

    init() {
        self.client = AppConfig.shared.makeClient()
        restorePersistedJoinedChannels()
    }

    func reloadClient() {
        client = AppConfig.shared.makeClient()
    }

    func loadChannels() async {
        isLoading = true
        reloadClient()
        do {
            let fetched = try await client.listChannels()
            mergeChannelList(fetched)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Merge server list with optimistic local entries (newly created channels may lag on graphd).
    private func mergeChannelList(_ fetched: [Channel]) {
        var byName = Dictionary(uniqueKeysWithValues: fetched.map { ($0.name, $0) })
        for channel in channels where byName[channel.name] == nil {
            byName[channel.name] = channel
        }
        for (name, visibility) in createdChannelVisibility where byName[name] == nil {
            byName[name] = Channel(
                nodeId: 0,
                name: name,
                description: nil,
                visibility: visibility,
                memberCount: 1
            )
        }
        let merged = byName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        channels = merged
        for channel in fetched {
            createdChannelVisibility.removeValue(forKey: channel.name)
        }
    }

    func createChannel(
        name: String,
        description: String?,
        visibility: ChannelVisibility
    ) async throws {
        reloadClient()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ForgeGraphError.apiError(400, "Channel name is required")
        }
        let channelId = try await client.createChannel(
            name: trimmed,
            description: description,
            visibility: visibility
        )
        try await joinChannelOffMain(trimmed)
        markJoined(trimmed)
        createdChannelVisibility[trimmed] = visibility
        storeMessages([], for: trimmed)
        insertOptimisticChannel(
            name: trimmed,
            nodeId: NodeId(channelId),
            description: description,
            visibility: visibility
        )
        await loadChannels()
        CoordinationAuditLog.shared.log(
            "Created #\(trimmed) (\(visibility.rawValue))",
            category: .channel
        )
    }

    /// Join public channels at boot so sends work; private channels require explicit opt-in.
    func syncMembership(force: Bool = false) async {
        if !force,
           let lastSync = lastMembershipSyncAt,
           Date().timeIntervalSince(lastSync) < membershipSyncCooldown {
            CoordinationAuditLog.shared.log(
                "Channel membership sync skipped — last sync \(Int(Date().timeIntervalSince(lastSync)))s ago",
                category: .channel
            )
            return
        }

        reloadClient()
        var joined = 0
        var failed = 0
        var skippedPrivate = 0
        for channel in channels {
            guard channel.visibility == .public else {
                skippedPrivate += 1
                continue
            }
            do {
                try await joinChannelOffMain(channel.name)
                markJoined(channel.name)
                joined += 1
            } catch {
                failed += 1
                print("[ChannelService] join(\(channel.name)) skipped: \(error)")
            }
        }
        lastMembershipSyncAt = Date()
        CoordinationAuditLog.shared.log(
            "Channel membership sync — joined \(joined) public, skipped \(skippedPrivate) private, failed \(failed)",
            category: .channel,
            level: failed > 0 ? .warn : .info
        )
    }

    func ensureJoined(channel: String) async {
        reloadClient()
        do {
            try await joinChannelOffMain(channel)
            markJoined(channel)
        } catch {
            print("[ChannelService] ensureJoined(\(channel)) failed: \(error)")
        }
    }

    /// Join then load history — single path used by the private-channel join button.
    func joinAndOpenThread(_ name: String) async -> Bool {
        cancelInflightHistory(for: name)
        guard await joinChannel(name) else { return false }
        await loadHistory(channel: name, force: true)
        return !needsJoin.contains(name)
    }

    /// Principal opts into a private channel. History loads separately so the join button stays responsive.
    func joinChannel(_ name: String) async -> Bool {
        CoordinationAuditLog.shared.log("Joining #\(name)", category: .channel)
        do {
            try await joinChannelOffMain(name)
            markJoined(name)
            CoordinationAuditLog.shared.log("Joined #\(name)", category: .channel)
            return true
        } catch {
            if error.isAlreadyChannelMember {
                markJoined(name)
                CoordinationAuditLog.shared.log("Already member of #\(name)", category: .channel)
                return true
            }
            let message = error.localizedDescription
            self.error = message
            CoordinationAuditLog.shared.log(
                "Join failed for #\(name): \(message)",
                category: .channel,
                level: .error
            )
            return false
        }
    }

    /// Map boot-time joined channel node ids to names after the channel list loads.
    func applyBootJoinedChannelIds(_ nodeIds: [NodeId]) {
        let joinedIds = Set(nodeIds)
        var applied = 0
        for channel in channels where joinedIds.contains(channel.nodeId) {
            markJoined(channel.name)
            applied += 1
        }
        if applied > 0 {
            CoordinationAuditLog.shared.log(
                "Boot membership restored for \(applied) channel(s)",
                category: .channel
            )
        }
    }

    /// Open a channel thread — always verifies with graphd for private channels.
    /// Returns true when history is loaded and the thread can render.
    func openChannelThread(_ channel: String) async -> Bool {
        CoordinationAuditLog.shared.log("Opening #\(channel)", category: .channel)
        if resolvedVisibility(for: channel) == .private {
            return await probePrivateChannel(channel)
        }
        if !joinedChannels.contains(channel) {
            await ensureJoined(channel: channel)
        }
        await loadHistory(channel: channel, force: true)
        return !needsJoin.contains(channel)
    }

    func requiresJoinGate(for channel: Channel) -> Bool {
        guard resolvedVisibility(for: channel.name) == .private else { return false }
        if joinedChannels.contains(channel.name), !needsJoin.contains(channel.name) {
            return false
        }
        return true
    }

    func resolvedChannel(named name: String) -> Channel? {
        if let channel = channels.first(where: { $0.name == name }) {
            return channel
        }
        if let visibility = createdChannelVisibility[name] {
            return Channel(
                nodeId: 0,
                name: name,
                description: nil,
                visibility: visibility,
                memberCount: 1
            )
        }
        return nil
    }

    func resolvedVisibility(for name: String) -> ChannelVisibility {
        resolvedChannel(named: name)?.visibility ?? .public
    }

    /// Thread messages for a specific channel — safe when switching channels on iPad.
    func threadMessages(for channel: String) -> [CoordMessage] {
        messages[channel] ?? []
    }

    /// Error banner for a channel thread (only when it matches the last load attempt).
    func threadError(for channel: String) -> String? {
        guard activeChannelName == channel else { return nil }
        return activeThreadError
    }

    func loadHistory(channel: String, limit: Int = 50, force: Bool = false) async {
        if loadingHistoryChannels.contains(channel) {
            if force {
                CoordinationAuditLog.shared.log(
                    "History force load — superseding in-flight load for #\(channel)",
                    category: .channel
                )
                cancelInflightHistory(for: channel)
            } else {
                CoordinationAuditLog.shared.log(
                    "History awaiting in-flight load for #\(channel)",
                    category: .channel
                )
                await waitForHistoryLoad(channel: channel)
                return
            }
        }

        let taskId = UUID()
        loadingHistoryChannels.insert(channel)
        inflightHistoryTaskIds[channel] = taskId
        defer {
            if inflightHistoryTaskIds[channel] == taskId {
                loadingHistoryChannels.remove(channel)
                inflightHistoryTaskIds.removeValue(forKey: channel)
            }
        }
        await performLoadHistory(
            channel: channel,
            limit: limit,
            force: force,
            taskId: taskId
        )
    }

    /// Yield until another caller's `loadHistory` finishes — avoids nested `Task { @MainActor }` deadlocks.
    private func waitForHistoryLoad(channel: String, maxWaitSeconds: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while loadingHistoryChannels.contains(channel), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func performLoadHistory(
        channel: String,
        limit: Int,
        force: Bool,
        taskId: UUID
    ) async {
        guard inflightHistoryTaskIds[channel] == taskId else { return }
        guard !Task.isCancelled else { return }

        CoordinationAuditLog.shared.log("History loading for #\(channel)", category: .channel)

        let isPrivate = resolvedVisibility(for: channel) == .private
        if !force,
           requiresJoinGate(for: Channel(nodeId: 0, name: channel, description: nil, visibility: isPrivate ? .private : .public, memberCount: 0)) {
            CoordinationAuditLog.shared.log(
                "History deferred for #\(channel) — join required",
                category: .channel
            )
            return
        }

        do {
            let history = try await fetchHistoryWithTimeout(channel: channel, limit: limit)
            guard inflightHistoryTaskIds[channel] == taskId, !Task.isCancelled else { return }
            markJoined(channel)
            applyHistory(history, for: channel)
            print("[ChannelService] loadHistory(\(channel)) OK — \(history.count) messages")
            CoordinationAuditLog.shared.log(
                "History loaded for #\(channel) — \(history.count) messages",
                category: .channel
            )
        } catch is HistoryFetchTimeoutError {
            guard inflightHistoryTaskIds[channel] == taskId else { return }
            let message = "Loading channel history timed out"
            if activeChannelName == channel {
                activeThreadError = message
            }
            self.error = message
            CoordinationAuditLog.shared.log(
                "History timed out for #\(channel) after \(Int(Self.historyFetchTimeoutSeconds))s",
                category: .channel,
                level: .error
            )
            print("[ChannelService] loadHistory(\(channel)) timed out")
        } catch {
            guard inflightHistoryTaskIds[channel] == taskId else { return }
            if isPrivate && error.isForbiddenChannelAccess {
                markAccessDenied(channel)
                CoordinationAuditLog.shared.log(
                    "Private #\(channel) — not a member",
                    category: .channel,
                    level: .warn
                )
                return
            }

            let message = error.localizedDescription
            if activeChannelName == channel {
                activeThreadError = message
            }
            self.error = message
            CoordinationAuditLog.shared.log(
                "History failed for #\(channel): \(message)",
                category: .channel,
                level: .error
            )
            print("[ChannelService] loadHistory(\(channel)) failed: \(error)")
        }
    }

    private func cancelInflightHistory(for channel: String) {
        loadingHistoryChannels.remove(channel)
        inflightHistoryTaskIds.removeValue(forKey: channel)
    }

    private func insertOptimisticChannel(
        name: String,
        nodeId: NodeId,
        description: String?,
        visibility: ChannelVisibility
    ) {
        let optimistic = Channel(
            nodeId: nodeId,
            name: name,
            description: description,
            visibility: visibility,
            memberCount: 1
        )
        var updated = channels.filter { $0.name != name }
        updated.append(optimistic)
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        channels = updated
    }

    /// Warm history cache for channels joined at boot.
    func preloadChannels(_ names: [String]) async {
        for name in names {
            await loadHistory(channel: name)
        }
    }

    func stopActiveChannelRefresh() {
        historyRefreshTask?.cancel()
        historyRefreshTask = nil
    }

    func send(channel: String, content: String, replyTo: NodeId? = nil) async {
        reloadClient()
        await ensureJoined(channel: channel)
        do {
            let messageId = try await client.sendChannelMessage(
                channel: channel,
                content: content,
                replyTo: replyTo
            )
            let localAgent = AppConfig.shared.agentName
            if let messageId {
                PeerNameResolver.shared.indexLiveChannelMessage(id: messageId, fromAgent: localAgent)
            }
            await loadHistory(channel: channel)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Append a message received via SSE (deduped by message id).
    func appendLiveMessage(channel: String, message: CoordMessage) {
        var channelMessages = messages[channel] ?? []
        guard !channelMessages.contains(where: { $0.id == message.id }) else { return }
        channelMessages.append(
            PeerNameResolver.shared.enrich(message, rosterAgents: rosterAgentNames())
        )
        channelMessages.sort { $0.sentAtUnixMs < $1.sentAtUnixMs }
        storeMessages(channelMessages, for: channel)
        updatePreview(channel: channel, message: message)
        if activeChannelName != channel {
            var unread = channelUnread
            unread[channel, default: 0] += 1
            channelUnread = unread
        }
    }

    func markChannelRead(_ channel: String) {
        var unread = channelUnread
        unread.removeValue(forKey: channel)
        channelUnread = unread
    }

    func setActiveChannel(_ channel: String?) {
        guard activeChannelName != channel else { return }
        stopActiveChannelRefresh()
        activeChannelName = channel
        if let channel {
            activeMessages = messages[channel] ?? []
            activeThreadError = nil
            markChannelRead(channel)
        } else {
            activeMessages = []
            activeThreadError = nil
        }
    }

    private func updatePreview(channel: String, message: CoordMessage) {
        let roster = rosterAgentNames()
        let enriched = PeerNameResolver.shared.enrich(message, rosterAgents: roster)
        let localAgent = AppConfig.shared.agentName
        let preview = ChannelPreview(
            lastContent: enriched.inboxPreview,
            lastFrom: PeerNameResolver.shared.displaySenderLabel(for: enriched, rosterAgents: roster),
            lastTimestamp: message.sentAtUnixMs,
            isOutbound: enriched.isFromLocalAgent(localAgent)
        )
        if let existing = channelPreviews[channel], existing.lastTimestamp > message.sentAtUnixMs {
            return
        }
        var previews = channelPreviews
        previews[channel] = preview
        channelPreviews = previews
    }

    /// Prefer the newest message with readable content for list previews.
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

    private struct HistoryFetchTimeoutError: Error {}

    private func fetchHistoryWithTimeout(channel: String, limit: Int) async throws -> [CoordMessage] {
        try await withThrowingTaskGroup(of: [CoordMessage].self) { group in
            group.addTask {
                try await self.fetchHistoryOffMain(channel: channel, limit: limit)
            }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(Self.historyFetchTimeoutSeconds * 1_000_000_000)
                )
                throw HistoryFetchTimeoutError()
            }
            guard let history = try await group.next() else {
                throw HistoryFetchTimeoutError()
            }
            group.cancelAll()
            return history
        }
    }

    /// Network I/O off the main actor so channel open/join cannot freeze navigation.
    private func fetchHistoryOffMain(channel: String, limit: Int) async throws -> [CoordMessage] {
        let config = AppConfig.shared
        let client = ForgeGraphClient(
            host: config.graphdHost,
            port: config.graphdPort,
            apiKey: config.apiKey,
            agentId: config.agentName
        )
        return try await client.channelHistory(name: channel, limit: limit)
    }

    private func joinChannelOffMain(_ name: String) async throws {
        let config = AppConfig.shared
        let client = ForgeGraphClient(
            host: config.graphdHost,
            port: config.graphdPort,
            apiKey: config.apiKey,
            agentId: config.agentName
        )
        try await client.joinChannel(name: name)
    }

    private func rosterAgentNames() -> [String] {
        var names = Set(PeerNameResolver.shared.nameMap.keys)
        names.remove(AppConfig.shared.agentName)
        return names.sorted()
    }

    private func joinedChannelsStorageKey() -> String {
        "\(Self.joinedChannelsDefaultsPrefix).\(AppConfig.shared.agentName)"
    }

    private func restorePersistedJoinedChannels() {
        let key = joinedChannelsStorageKey()
        guard let names = UserDefaults.standard.array(forKey: key) as? [String] else { return }
        joinedChannels = Set(names)
        if !names.isEmpty, !AppConfig.isConstructing {
            CoordinationAuditLog.shared.log(
                "Restored \(names.count) persisted channel membership(s)",
                category: .channel
            )
        }
    }

    private func persistJoinedChannels() {
        UserDefaults.standard.set(
            Array(joinedChannels).sorted(),
            forKey: joinedChannelsStorageKey()
        )
    }

    /// Re-join private channels we were a member of before relaunch.
    func syncPersistedPrivateMembership() async {
        reloadClient()
        var joined = 0
        for channel in channels where channel.visibility == .private && joinedChannels.contains(channel.name) {
            do {
                try await joinChannelOffMain(channel.name)
                markJoined(channel.name)
                joined += 1
            } catch where error.isAlreadyChannelMember {
                markJoined(channel.name)
                joined += 1
            } catch {
                print("[ChannelService] persisted join(\(channel.name)) skipped: \(error)")
            }
        }
        if joined > 0 {
            CoordinationAuditLog.shared.log(
                "Restored server membership for \(joined) private channel(s)",
                category: .channel
            )
        }
    }

    private func probePrivateChannel(_ channel: String) async -> Bool {
        if requiresJoinGate(for: Channel(nodeId: 0, name: channel, description: nil, visibility: .private, memberCount: 0)) {
            CoordinationAuditLog.shared.log(
                "Probe skipped for #\(channel) — join gate active",
                category: .channel
            )
            return false
        }
        await loadHistory(channel: channel, force: true)
        return !needsJoin.contains(channel)
    }

    private func applyHistory(_ history: [CoordMessage], for channel: String) {
        let roster = rosterAgentNames()
        storeMessages(
            PeerNameResolver.shared.enrichChannelBatch(history, rosterAgents: roster),
            for: channel
        )
        if let last = bestPreviewMessage(from: history) {
            updatePreview(channel: channel, message: last)
        }
        if channels.contains(where: { $0.name == channel }) {
            createdChannelVisibility.removeValue(forKey: channel)
        }
        if activeChannelName == channel {
            activeThreadError = nil
        }
        error = nil
    }

    private func markJoined(_ channel: String) {
        joinedChannels.insert(channel)
        privateAccessDenied.remove(channel)
        needsJoin.remove(channel)
        persistJoinedChannels()
    }

    private func markAccessDenied(_ channel: String) {
        privateAccessDenied.insert(channel)
        needsJoin.insert(channel)
        joinedChannels.remove(channel)
        persistJoinedChannels()
        var updated = messages
        updated.removeValue(forKey: channel)
        messages = updated
        if activeChannelName == channel {
            activeMessages = []
            activeThreadError = nil
        }
    }

    /// Reassign so `@Published` emits — in-place dictionary mutation does not refresh SwiftUI.
    private func storeMessages(_ channelMessages: [CoordMessage], for channel: String) {
        var updated = messages
        updated[channel] = channelMessages
        messages = updated
        if activeChannelName == channel {
            activeMessages = channelMessages
        }
    }
}