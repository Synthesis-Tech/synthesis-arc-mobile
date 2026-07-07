import Foundation
import Combine

/// Coordinates fleet data from forge-graphd + blackboard
@MainActor
class FleetService: ObservableObject {
    @Published var peers: [Peer] = []
    @Published var blackboard: [BlackboardEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var graphdHealthy = false
    @Published var streamConnected = false
    @Published private(set) var isBooted = false
    @Published var isBootstrapping = false
    @Published var myPeerId: String?
    @Published var mySessionId: String?
    @Published private(set) var roster: FleetRoster = .empty
    @Published private(set) var exceptionCount: Int = 0
    /// Channel node ids joined at last boot — mapped to names after channel list loads.
    private(set) var lastBootJoinedChannelIds: [NodeId] = []

    private var client: ForgeGraphClient
    private var refreshTimer: Timer?
    private weak var dmService: DMService?
    private weak var channelService: ChannelService?
    private var dmCancellable: AnyCancellable?

    private let pollIntervalLive: TimeInterval = 120
    private let pollIntervalFallback: TimeInterval = 30

    init() {
        self.client = AppConfig.shared.makeClient()
        reloadRoster()
        startPolling(runImmediateRefresh: false)
    }

    func reloadClient() {
        client = AppConfig.shared.makeClient()
    }

    func reloadRoster() {
        roster = FleetRosterLoader.load(overridePath: AppConfig.shared.fleetRosterPath)
    }

    func attachDMService(_ dmService: DMService) {
        self.dmService = dmService
        dmCancellable = dmService.$inboundMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshExceptionCount()
            }
        refreshExceptionCount()
    }

    func attachChannelService(_ channelService: ChannelService) {
        self.channelService = channelService
    }

    /// Peers ranked by SignalRanker (score >= 50).
    func peersNeedingAttention(watchlist: Set<String>) -> [Peer] {
        SignalRanker.needsAttention(
            peers: peers,
            watchlist: watchlist,
            dmUnreadAgents: dmUnreadAgents
        )
    }

    func signalScore(for peer: Peer, watchlist: Set<String>) -> Int {
        SignalRanker.score(
            peer: peer,
            watchlist: watchlist,
            dmUnreadAgents: dmUnreadAgents
        )
    }

    func setStreamConnected(_ connected: Bool) {
        streamConnected = connected
        restartPolling()
    }

    /// Build fleet sections: watchlist first, then departments (collapsible in the view).
    func fleetSections(searchText: String, watchlist: Set<String>) -> [FleetSection] {
        let filtered = peers.filteredForFleetSearch(searchText)
        var sections: [FleetSection] = []

        let pinned = filtered.filter { watchlist.contains($0.agentName) }.fleetSorted()
        if !pinned.isEmpty {
            sections.append(FleetSection(id: "watchlist", title: "Watchlist", peers: pinned))
        }

        var grouped: [String: [Peer]] = [:]
        for peer in filtered {
            let key = roster.departmentKey(for: peer.agentName)
            grouped[key, default: []].append(peer)
        }

        for key in roster.orderedDepartmentKeys {
            guard let deptPeers = grouped[key], !deptPeers.isEmpty else { continue }
            sections.append(
                FleetSection(
                    id: key,
                    title: roster.label(for: key),
                    peers: deptPeers.fleetSorted()
                )
            )
        }

        return sections
    }

    /// Apply a live blackboard update from SSE without a full refresh.
    func applyBlackboardUpdate(key: String, value: String?, setBy: String?, timestamp: Int64?) {
        let updatedMs = (timestamp ?? Int64(Date().timeIntervalSince1970)) * 1000

        if let value {
            let entry = BlackboardEntry(
                key: key,
                value: value,
                setBy: nil,
                updatedAtUnixMs: updatedMs,
                ttlSeconds: nil
            )
            if let idx = blackboard.firstIndex(where: { $0.key == key }) {
                blackboard[idx] = entry
            } else {
                blackboard.insert(entry, at: 0)
            }
            blackboard.sort { $0.updatedAtUnixMs > $1.updatedAtUnixMs }
        } else {
            blackboard.removeAll { $0.key == key }
        }

        if key.hasSuffix(".status") {
            let agentName = String(key.dropLast(".status".count))
            if let idx = peers.firstIndex(where: { $0.agentName == agentName }) {
                peers[idx].blackboardStatus = value
                if let value {
                    for state in ["woke_up", "reconstructed", "performed", "degraded"] {
                        if value.contains(state) {
                            peers[idx].bootState = state
                            break
                        }
                    }
                }
            }
        }
        refreshExceptionCount()
    }

    /// Boot as a peer — register session, join channels, snapshot state
    func bootAsPeer(reason: String = "manual") async {
        CoordinationAuditLog.shared.log("Boot requested (\(reason))", category: .boot)
        let config = AppConfig.shared
        reloadClient()
        reloadRoster()

        guard !config.apiKey.isEmpty else {
            error = "API key required — open Settings"
            isBooted = false
            PrincipalContext.shared.clear()
            return
        }

        do {
            let response = try await client.boot(
                channels: ["engineering", "ops"],
                summary: "\(config.agentName) — Forge Commander"
            )
            myPeerId = String(response.peerId)
            mySessionId = String(response.sessionId)
            lastBootJoinedChannelIds = response.joinedChannels
            graphdHealthy = true
            error = nil
            isBooted = true

            print("[FleetService] BOOT OK — peer: \(response.peerId), session: \(response.sessionId), pending DMs: \(response.pendingMessages.count)")
            CoordinationAuditLog.shared.log(
                "Boot OK — peer \(response.peerId), session \(response.sessionId), pending DMs \(response.pendingMessages.count)",
                category: .boot
            )

            PrincipalContext.shared.configure(
                peerId: response.peerId,
                sessionId: response.sessionId,
                agentName: config.agentName
            )

            blackboard = response.blackboardSnapshot.sorted {
                $0.updatedAtUnixMs > $1.updatedAtUnixMs
            }
            PeerNameResolver.shared.indexBlackboard(blackboard)

            if !response.pendingMessages.isEmpty {
                let rosterNames = self.roster.allMemberNames
                let enriched = PeerNameResolver.shared.enrichMessageBatch(
                    response.pendingMessages,
                    rosterAgents: rosterNames
                )
                dmService?.seedInbound(enriched)
            }

            if !response.errors.isEmpty {
                let detail = response.errors.map { "\($0.channel): \($0.reason)" }.joined(separator: "; ")
                print("[FleetService] boot channel join warnings: \(response.errors)")
                CoordinationAuditLog.shared.log(
                    "Boot channel warnings: \(detail)",
                    category: .boot,
                    level: .warn
                )
            }
        } catch {
            print("[FleetService] BOOT FAILED: \(error)")
            self.error = "Boot failed: \(error.localizedDescription)"
            isBooted = false
            PrincipalContext.shared.clear()
            CoordinationAuditLog.shared.log(
                "Boot failed: \(error.localizedDescription)",
                category: .boot,
                level: .error
            )
        }
    }

    func refresh() async {
        isLoading = true
        error = nil
        reloadClient()
        reloadRoster()

        let config = AppConfig.shared
        guard !config.apiKey.isEmpty else {
            error = "API key required — open Settings"
            graphdHealthy = false
            isLoading = false
            return
        }

        do {
            async let peersResult = client.listPeers()
            async let boardResult = client.listBlackboard()
            async let healthResult = client.health()

            var fetchedPeers = try await peersResult
            let fetchedBoard = try await boardResult
            graphdHealthy = (try? await healthResult) ?? false

            fetchedPeers = fetchedPeers.deduplicatedByAgent()

            for i in fetchedPeers.indices {
                let statusKey = "\(fetchedPeers[i].agentName).status"
                if let entry = fetchedBoard.first(where: { $0.key == statusKey }) {
                    fetchedPeers[i].blackboardStatus = entry.value
                    for state in ["woke_up", "reconstructed", "performed", "degraded"] {
                        if entry.value.contains(state) {
                            fetchedPeers[i].bootState = state
                            break
                        }
                    }
                }
            }

            if !config.showOfflineAgents {
                fetchedPeers = fetchedPeers.filter { $0.status != .offline }
            }

            self.peers = fetchedPeers.fleetSorted()
            self.blackboard = fetchedBoard.sorted { $0.updatedAtUnixMs > $1.updatedAtUnixMs }
            PeerNameResolver.shared.indexFleetAgents(self.peers)
            PeerNameResolver.shared.indexBlackboard(self.blackboard)
            dmService?.reindexStoredMessages()
            self.error = nil
            refreshExceptionCount()
        } catch is CancellationError {
            CoordinationAuditLog.shared.log("Fleet refresh cancelled", category: .network)
        } catch {
            self.error = error.localizedDescription
            self.graphdHealthy = false
            CoordinationAuditLog.shared.log(
                "Fleet refresh failed: \(error.localizedDescription)",
                category: .network,
                level: .warn
            )
        }

        isLoading = false
    }

    /// Channel list, membership, fleet refresh — run after boot; safe to overlap with SSE connect.
    func completeBootSetup() async {
        CoordinationAuditLog.shared.log("Boot setup — loading channels and fleet", category: .boot)
        await channelService?.loadChannels()
        channelService?.applyBootJoinedChannelIds(lastBootJoinedChannelIds)
        await channelService?.syncPersistedPrivateMembership()
        await channelService?.syncMembership(force: true)
        await refresh()
        // Warm only default channels; full history loads when a thread is opened.
        Task(priority: .utility) {
            await channelService?.preloadChannels(["engineering", "ops"])
        }
        CoordinationAuditLog.shared.log("Boot setup complete", category: .boot)
    }

    private func startPolling(runImmediateRefresh: Bool = true) {
        restartPolling()
        if runImmediateRefresh {
            Task { await refresh() }
        }
    }

    private func restartPolling() {
        refreshTimer?.invalidate()
        let interval = streamConnected ? pollIntervalLive : pollIntervalFallback
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    private var dmUnreadAgents: Set<String> {
        guard let dmService else { return [] }
        return Set(dmService.conversationSummaries().map(\.senderAgentName))
    }

    private func refreshExceptionCount() {
        let watchlistRaw = UserDefaults.standard.string(forKey: FleetWatchlist.storageKey) ?? ""
        let watchlist = FleetWatchlist.decode(watchlistRaw)
        exceptionCount = SignalRanker.needsAttention(
            peers: peers,
            watchlist: watchlist,
            dmUnreadAgents: dmUnreadAgents
        ).count
    }

    /// Re-boot peer session and restart live services after settings change.
    func applySettingsAndReconnect(
        streamService: CoordinationStreamService,
        channelService: ChannelService,
        dmService: DMService
    ) async {
        CoordinationAuditLog.shared.log("Apply & Reconnect started", category: .settings)
        error = nil
        reloadClient()
        reloadRoster()
        channelService.reloadClient()
        streamService.stop()
        dmService.stopPolling()
        isBootstrapping = true
        defer { isBootstrapping = false }
        await bootAsPeer(reason: "apply-reconnect")
        CoordinationHotLayer.shared.start(
            fleetService: self,
            dmService: dmService,
            channelService: channelService,
            streamService: streamService
        )
        streamService.start(force: true)
        await completeBootSetup()
    }
}
