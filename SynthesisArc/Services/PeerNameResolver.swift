import Foundation

/// Resolves NodeIds and agent names for display.
@MainActor
class PeerNameResolver: ObservableObject {
    static let shared = PeerNameResolver()

    @Published private(set) var nameMap: [String: String] = [:]
    /// Session NodeId string → agent_name (from blackboard `*.status` set_by fields).
    @Published private(set) var sessionToAgent: [String: String] = [:]
    /// Message NodeId string → agent_name (from live SSE channel events).
    @Published private(set) var messageIdToAgent: [String: String] = [:]

    private var client: ForgeGraphClient

    init() {
        self.client = AppConfig.shared.makeClient()
        hydratePersistedSessions()
    }

    func refresh() async {
        client = AppConfig.shared.makeClient()
        do {
            let peers = try await client.listPeers()
            indexFleetAgents(peers.deduplicatedByAgent())
        } catch {
            // Keep existing cache on failure
        }
    }

    /// Register fleet agent slugs so mention/signature inference and display labels resolve.
    func indexFleetAgents(_ peers: [Peer]) {
        var map = nameMap
        for peer in peers where !peer.agentName.isEmpty {
            map[peer.agentName] = peer.agentName
        }
        nameMap = map
    }

    private static let knownSessionsKeyPrefix = "peer.sessions."

    /// Index blackboard entries to map session NodeIds → agent names (merged, not replaced).
    func indexBlackboard(_ entries: [BlackboardEntry]) {
        for entry in entries {
            guard entry.key.hasSuffix(".status"), let setBy = entry.setBy else { continue }
            let agent = String(entry.key.dropLast(".status".count))
            indexSession(String(setBy), for: agent)
        }
    }

    /// Wire the operator's current boot identity — X-Agent-Id is not stored on historical messages.
    func indexBootIdentity(peerId: NodeId, sessionId: NodeId, agentName: String) {
        var sessions = sessionToAgent
        indexSession(String(sessionId), for: agentName)
        indexSession(String(peerId), for: agentName)
    }

    /// Resolve a sender session NodeId to an agent name, if known.
    func agentName(forSession sessionId: NodeId) -> String? {
        let key = String(sessionId)
        if let agent = sessionToAgent[key] {
            return agent
        }
        for agent in fleetAgentSlugs() where knownSessions(for: agent).contains(key) {
            indexSession(key, for: agent)
            return agent
        }
        return nil
    }

    private func fleetAgentSlugs() -> [String] {
        Array(Set(nameMap.values)).sorted()
    }

    private func hydratePersistedSessions() {
        var sessions = sessionToAgent
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            guard key.hasPrefix(Self.knownSessionsKeyPrefix),
                  let raw = value as? String else { continue }
            let agent = String(key.dropFirst(Self.knownSessionsKeyPrefix.count))
            guard !agent.isEmpty else { continue }
            for sessionId in raw.split(separator: ",") {
                sessions[String(sessionId)] = agent
            }
        }
        sessionToAgent = sessions
    }

    func indexSession(_ sessionId: String, for agent: String) {
        guard !sessionId.isEmpty, !agent.isEmpty else { return }
        var sessions = sessionToAgent
        sessions[sessionId] = agent
        sessionToAgent = sessions
        rememberSession(sessionId, for: agent)
    }

    private func knownSessions(for agent: String) -> Set<String> {
        let key = Self.knownSessionsKeyPrefix + agent
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        guard !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").map(String.init))
    }

    private func rememberSession(_ sessionId: String, for agent: String) {
        var sessions = knownSessions(for: agent)
        guard sessions.insert(sessionId).inserted else { return }
        let key = Self.knownSessionsKeyPrefix + agent
        UserDefaults.standard.set(sessions.sorted().joined(separator: ","), forKey: key)
    }

    /// Record agent identity from live SSE events (REST history only has session ids).
    func indexLiveChannelMessage(id: NodeId, fromAgent: String) {
        indexLiveMessage(id: id, fromAgent: fromAgent)
    }

    func indexLiveMessage(id: NodeId, fromAgent: String) {
        guard !fromAgent.isEmpty else { return }
        messageIdToAgent[String(id)] = fromAgent
    }

    /// Fill agent-name fields for REST-sourced messages (poll, boot, history).
    func enrich(_ message: CoordMessage, rosterAgents: [String] = []) -> CoordMessage {
        var enriched = message
        if enriched.fromAgentName == nil,
           let agent = messageIdToAgent[String(enriched.id)] {
            enriched.fromAgentName = agent
        }
        if enriched.fromAgentName == nil, let from = enriched.from,
           let agent = agentName(forSession: from) {
            enriched.fromAgentName = agent
        }
        if enriched.fromAgentName == nil, !rosterAgents.isEmpty,
           let inferred = MessageAgentResolver.inferAuthorFromSignature(
               in: enriched.content,
               rosterAgents: rosterAgents
           ) {
            enriched.fromAgentName = inferred
        }
        if let from = enriched.from, let agent = enriched.fromAgentName, !agent.allSatisfy(\.isNumber) {
            indexSession(String(from), for: agent)
        }
        return enriched
    }

    /// Multi-pass enrichment so session ids learned from any message apply to the whole batch.
    func enrichMessageBatch(_ messages: [CoordMessage], rosterAgents: [String] = []) -> [CoordMessage] {
        let pass1 = messages.map { enrich($0, rosterAgents: rosterAgents) }
        var sessionAgents: [String: String] = [:]
        for msg in pass1 {
            if let agent = msg.fromAgentName, let from = msg.from, !agent.allSatisfy(\.isNumber) {
                sessionAgents[String(from)] = agent
            }
        }
        return pass1.map { msg in
            var updated = msg
            if updated.fromAgentName == nil,
               let from = updated.from,
               let agent = sessionAgents[String(from)] {
                updated.fromAgentName = agent
                indexSession(String(from), for: agent)
            }
            return updated
        }
    }

    func enrichChannelBatch(_ messages: [CoordMessage], rosterAgents: [String] = []) -> [CoordMessage] {
        enrichMessageBatch(messages, rosterAgents: rosterAgents)
    }

    /// Human-readable sender label for channel/DM bubbles.
    func displaySenderLabel(for message: CoordMessage, rosterAgents: [String]) -> String {
        let enriched = enrich(message, rosterAgents: rosterAgents)
        if let agent = MessageAgentResolver.agentName(for: enriched, rosterAgents: rosterAgents) {
            return formatName(agent)
        }
        return resolve(enriched.from)
    }

    /// Agent slug when known — used for avatars and actions.
    func resolvedAgentSlug(for message: CoordMessage, rosterAgents: [String]) -> String? {
        let enriched = enrich(message, rosterAgents: rosterAgents)
        return MessageAgentResolver.agentName(for: enriched, rosterAgents: rosterAgents)
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