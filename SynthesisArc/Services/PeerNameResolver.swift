import Foundation

/// Resolves NodeIds and agent names for display.
@MainActor
class PeerNameResolver: ObservableObject {
    static let shared = PeerNameResolver()

    @Published private(set) var nameMap: [String: String] = [:]
    /// Session NodeId string → agent_name (from blackboard `*.status` set_by fields).
    @Published private(set) var sessionToAgent: [String: String] = [:]

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

    /// Index blackboard entries to map session NodeIds → agent names.
    func indexBlackboard(_ entries: [BlackboardEntry]) {
        var sessions: [String: String] = [:]
        for entry in entries {
            guard entry.key.hasSuffix(".status"), let setBy = entry.setBy else { continue }
            let agent = String(entry.key.dropLast(".status".count))
            sessions[String(setBy)] = agent
        }
        sessionToAgent = sessions
    }

    /// Resolve a sender session NodeId to an agent name, if known.
    func agentName(forSession sessionId: NodeId) -> String? {
        sessionToAgent[String(sessionId)]
    }

    /// Fill agent-name fields for REST-sourced messages (poll, boot, history).
    func enrich(_ message: CoordMessage) -> CoordMessage {
        var enriched = message
        if enriched.fromAgentName == nil, let from = enriched.from,
           let agent = agentName(forSession: from) {
            enriched.fromAgentName = agent
        }
        return enriched
    }

    /// Resolve a session NodeId string to a display name
    func resolve(_ nodeId: String) -> String {
        if let agent = sessionToAgent[nodeId] {
            return formatName(agent)
        }
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