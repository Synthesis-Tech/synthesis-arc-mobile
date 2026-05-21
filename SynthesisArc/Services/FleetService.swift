import Foundation
import Combine

/// Coordinates fleet data from daemon + blackboard
@MainActor
class FleetService: ObservableObject {
    @Published var peers: [Peer] = []
    @Published var blackboard: [BlackboardEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var daemonHealthy = false
    @Published var myPeerId: String?

    private var daemon: DaemonClient
    private var refreshTimer: Timer?

    init() {
        let config = AppConfig.shared
        self.daemon = DaemonClient(host: config.daemonHost, port: config.daemonPort)
        startPolling()
    }

    /// Boot this app as a peer — registers with daemon, joins channels
    func bootAsPeer() async {
        do {
            let response = try await daemon.boot(
                name: "daniel-willitzer",
                channels: ["engineering", "ops"],
                summary: "Daniel Willitzer — iOS Fleet App"
            )
            myPeerId = response.peerId.value
            daemonHealthy = response.daemonHealthy

            // Pre-populate blackboard from boot response
            if let snapshot = response.blackboardSnapshot {
                self.blackboard = snapshot.sorted { $0.updatedAt > $1.updatedAt }
            }
        } catch {
            // Fall back to polling if boot fails
            self.error = "Boot failed: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        isLoading = true
        error = nil

        do {
            // Parallel fetch: peers + blackboard + health
            async let peersResult = daemon.listPeers()
            async let boardResult = daemon.listBlackboard()
            async let healthResult = daemon.health()

            var fetchedPeers = try await peersResult
            let fetchedBoard = try await boardResult
            daemonHealthy = (try? await healthResult) ?? false

            // Merge blackboard status into peers
            for i in fetchedPeers.indices {
                let statusKey = "\(fetchedPeers[i].name).status"
                if let entry = fetchedBoard.first(where: { $0.key == statusKey }) {
                    fetchedPeers[i].blackboardStatus = entry.value
                    // Extract boot state from blackboard status string
                    for state in ["woke_up", "reconstructed", "performed", "degraded"] {
                        if entry.value.contains(state) {
                            fetchedPeers[i].bootState = state
                            break
                        }
                    }
                }
            }

            // Sort: active (green) first, then by name
            fetchedPeers.sort { a, b in
                if a.statusColor != b.statusColor {
                    return a.statusColor.sortOrder < b.statusColor.sortOrder
                }
                return a.name < b.name
            }

            self.peers = fetchedPeers
            self.blackboard = fetchedBoard.sorted { $0.updatedAt > $1.updatedAt }
            self.error = nil
        } catch {
            self.error = error.localizedDescription
            self.daemonHealthy = false
        }

        isLoading = false
    }

    private func startPolling() {
        // Poll every 10 seconds — SSE replaces this when wired
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        // Initial load
        Task { await refresh() }
    }

    nonisolated func stopPolling() {
        // Timer cleanup handled by ARC — Timer invalidates on dealloc
    }
}

// MARK: - Sort support

extension Peer.StatusColor {
    var sortOrder: Int {
        switch self {
        case .green: return 0
        case .yellow: return 1
        case .red: return 2
        case .gray: return 3
        }
    }
}
