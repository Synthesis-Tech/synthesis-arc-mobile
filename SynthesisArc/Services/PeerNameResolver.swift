import Foundation

/// Resolves NodeIds and agent names for display.
@MainActor
class PeerNameResolver: ObservableObject {
    static let shared = PeerNameResolver()

    @Published private(set) var nameMap: [String: String] = [:]

    private var client: ForgeGraphClient

    init() {
        self.client = AppConfig.shared.makeClient()
    }

    func refresh() async {
        client = AppConfig.shared.makeClient()
        do {
            let peers = try await client.listPeers()
            var map: [String: String] = [:]
            for peer in peers.deduplicatedByAgent() {
                map[peer.agentName] = peer.agentName
            }
            self.nameMap = map
        } catch {
            // Keep existing cache on failure
        }
    }

    /// Resolve a session NodeId string to a display name
    func resolve(_ nodeId: String) -> String {
        if let name = nameMap[nodeId] {
            return formatName(name)
        }
        if nodeId.allSatisfy(\.isNumber), nodeId.count > 6 {
            return "#\(nodeId.suffix(6))"
        }
        return formatName(nodeId)
    }

    func resolve(_ nodeId: NodeId?) -> String {
        guard let nodeId else { return "unknown" }
        return resolve(String(nodeId))
    }

    private func formatName(_ name: String) -> String {
        name.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}