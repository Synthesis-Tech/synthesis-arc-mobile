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
    @Published var myPeerId: String?
    @Published var mySessionId: String?
    @Published private(set) var roster: FleetRoster = .empty
    @Published private(set) var exceptionCount: Int = 0

    private var client: ForgeGraphClient
    private var refreshTimer: Timer?
    private weak var dmService: DMService?
    private var dmCancellable: AnyCancellable?

    private let pollIntervalLive: TimeInterval = 120
    private let pollIntervalFallback: TimeInterval = 30

    init() {
        self.client = AppConfig.shared.makeClient()
        reloadRoster()
        startPolling()
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
    func bootAsPeer() async {
        let config = AppConfig.shared
        reloadClient()
        reloadRoster()

        guard !config.apiKey.isEmpty else {
            error = "API key required — open Settings"
            return
        }

        do {
            let response = try await client.boot(
                channels: ["engineering", "ops"],
                summary: "\(config.agentName) — Synthesis Arc Fleet"
            )
            myPeerId = String(response.peerId)
            mySessionId = String(response.sessionId)
            graphdHealthy = true
            error = nil

            print("[FleetService] BOOT OK — peer: \(response.peerId), session: \(response.sessionId), pending DMs: \(response.pendingMessages.count)")

            blackboard = response.blackboardSnapshot.sorted {
                $0.updatedAtUnixMs > $1.updatedAtUnixMs
            }
            await refresh()
        } catch {
            print("[FleetService] BOOT FAILED: \(error)")
            self.error = "Boot failed: \(error.localizedDescription)"
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
            self.error = nil
            refreshExceptionCount()
        } catch {
            self.error = error.localizedDescription
            self.graphdHealthy = false
        }

        isLoading = false
    }

    private func startPolling() {
        restartPolling()
        Task { await refresh() }
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
        exceptionCount = SignalRanker.needsAttention(
            peers: peers,
            watchlist: [],
            dmUnreadAgents: dmUnreadAgents
        ).count
    }
}