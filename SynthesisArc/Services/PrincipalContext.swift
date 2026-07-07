import Foundation

/// Validated operator identity from boot — single source of truth after API key + X-Agent-Id check.
@MainActor
final class PrincipalContext: ObservableObject {
    static let shared = PrincipalContext()

    @Published private(set) var agentName: String = ""
    @Published private(set) var peerId: NodeId?
    @Published private(set) var sessionId: NodeId?
    @Published private(set) var isConfigured = false

    private init() {}

    func configure(peerId: NodeId, sessionId: NodeId, agentName: String) {
        self.agentName = agentName
        self.peerId = peerId
        self.sessionId = sessionId
        self.isConfigured = true
        PeerNameResolver.shared.indexBootIdentity(
            peerId: peerId,
            sessionId: sessionId,
            agentName: agentName
        )
    }

    func clear() {
        agentName = ""
        peerId = nil
        sessionId = nil
        isConfigured = false
    }

    var localAgentName: String {
        isConfigured ? agentName : AppConfig.shared.agentName
    }

    /// Whether a history message session belongs to this principal.
    func ownsSession(_ from: NodeId?) -> Bool {
        guard let from else { return false }
        let key = String(from)
        if let sessionId, key == String(sessionId) { return true }
        if let peerId, key == String(peerId) { return true }
        return PeerNameResolver.shared.agentName(forSession: from) == agentName
    }
}