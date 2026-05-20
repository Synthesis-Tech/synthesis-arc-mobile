import Foundation

/// Resolves peer IDs to agent names using the fleet peer registry.
/// Maintains a local cache refreshed from list-peers.
@MainActor
class PeerNameResolver: ObservableObject {
    static let shared = PeerNameResolver()

    /// peer_id → agent name cache
    @Published private(set) var nameMap: [String: String] = [:]

    private let daemon = DaemonClient()

    /// Refresh the name map from the daemon
    func refresh() async {
        do {
            let peers = try await daemon.listPeers()
            var map: [String: String] = [:]
            for peer in peers {
                map[peer.id] = peer.name
            }
            self.nameMap = map
        } catch {
            // Keep existing cache on failure
        }
    }

    /// Resolve a peer ID to a display name
    func resolve(_ peerId: String) -> String {
        if let name = nameMap[peerId] {
            return formatName(name)
        }
        // Fallback: truncated peer ID
        return String(peerId.prefix(8))
    }

    /// Format agent name for display: "kenji-okafor" → "Kenji Okafor"
    private func formatName(_ name: String) -> String {
        name.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
