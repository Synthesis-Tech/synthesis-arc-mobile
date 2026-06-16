import Foundation

// MARK: - Shared Types

typealias NodeId = UInt64

enum PeerStatus: String, Codable {
    case active = "Active"
    case idle = "Idle"
    case thinking = "Thinking"
    case stale = "Stale"
    case offline = "Offline"
}

enum MessageType: String, Codable {
    case text = "Text"
    case query = "Query"
    case response = "Response"
    case handoff = "Handoff"
    case broadcast = "Broadcast"
}

enum ChannelVisibility: String, Codable {
    case `public` = "Public"
    case `private` = "Private"
}

// MARK: - Peer

struct Peer: Codable, Identifiable {
    let agentName: String
    let pid: UInt32?
    let cwd: String?
    let gitRoot: String?
    let summary: String?
    let status: PeerStatus

    var id: String { agentName }
    var name: String { agentName }

    var blackboardStatus: String?
    var bootState: String?

    enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case pid, cwd
        case gitRoot = "git_root"
        case summary, status
    }

    var statusColor: StatusColor {
        switch status {
        case .active, .thinking: return .green
        case .idle: return .yellow
        case .stale: return .yellow
        case .offline: return .red
        }
    }

    enum StatusColor {
        case green, yellow, red, gray
    }
}

// MARK: - Channel Preview

struct ChannelPreview: Equatable {
    let lastContent: String
    let lastFrom: String
    let lastTimestamp: Int64

    var previewLine: String {
        let sender = lastFrom.isEmpty ? "unknown" : lastFrom
        return "\(sender): \(lastContent)"
    }

    var relativeTime: String {
        TimeFormat.relative(fromUnixMs: lastTimestamp)
    }
}

// MARK: - Channel

struct Channel: Codable, Identifiable {
    let nodeId: NodeId
    let name: String
    let description: String?
    let visibility: ChannelVisibility
    let memberCount: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case nodeId = "id"
        case name, description, visibility
        case memberCount = "member_count"
    }
}

// MARK: - Coordination Message (channels + DMs)

struct CoordMessage: Codable, Identifiable {
    let id: NodeId
    let from: NodeId?
    let channel: NodeId?
    let dmTo: NodeId?
    let content: String
    let messageType: MessageType
    let replyTo: NodeId?
    let sentAtUnixMs: Int64
    let pinned: Bool
    /// Populated for SSE-sourced messages where sender is an agent name, not a NodeId.
    var fromAgentName: String?
    /// Populated for optimistic outbound DMs (local agent → peer agent name).
    var toAgentName: String?

    enum CodingKeys: String, CodingKey {
        case id, from, channel, content, pinned
        case dmTo = "dm_to"
        case messageType = "message_type"
        case replyTo = "reply_to"
        case sentAtUnixMs = "sent_at_unix_ms"
    }

    /// Whether this message was sent by `peerAgentName` in a bilateral thread.
    func isFromPeer(peerAgentName: String, localAgent: String) -> Bool {
        if let from = fromAgentName {
            if from == localAgent { return false }
            return from == peerAgentName
        }
        if let to = toAgentName {
            return to == peerAgentName
        }
        // REST-polled inbound DMs: sender session id in `from`, no agent name yet.
        return from != nil
    }

    func isFromLocalAgent(_ localAgent: String) -> Bool {
        fromAgentName == localAgent || toAgentName != nil
    }

    var fromNodeId: String {
        from.map(String.init) ?? "unknown"
    }

    var sentAtDisplay: String {
        if sentAtUnixMs > 0 {
            return TimeFormat.fromUnixMs(sentAtUnixMs)
        }
        return ""
    }

    /// Build a display message from an SSE peer_message event.
    static func fromSSE(messageId: UInt64, from: String, content: String, timestamp: Int64) -> CoordMessage {
        CoordMessage(
            id: messageId,
            from: nil,
            channel: nil,
            dmTo: nil,
            content: content,
            messageType: .text,
            replyTo: nil,
            sentAtUnixMs: timestamp * 1000,
            pinned: false,
            fromAgentName: from
        )
    }

    /// Build a display message from an SSE channel_message event.
    static func fromSSEChannel(
        messageId: UInt64,
        from: String,
        content: String,
        timestamp: Int64
    ) -> CoordMessage {
        CoordMessage(
            id: messageId,
            from: nil,
            channel: nil,
            dmTo: nil,
            content: content,
            messageType: .text,
            replyTo: nil,
            sentAtUnixMs: timestamp * 1000,
            pinned: false,
            fromAgentName: from
        )
    }
}

// MARK: - Blackboard

struct BlackboardEntry: Codable, Identifiable {
    let key: String
    let value: String
    let setBy: NodeId?
    let updatedAtUnixMs: Int64
    let ttlSeconds: Int64?

    var id: String { key }

    var updatedAt: String { TimeFormat.fromUnixMs(updatedAtUnixMs) }

    enum CodingKeys: String, CodingKey {
        case key, value
        case setBy = "set_by"
        case updatedAtUnixMs = "updated_at_unix_ms"
        case ttlSeconds = "ttl_seconds"
    }
}

// MARK: - Boot

struct BootError: Codable {
    let channel: String
    let reason: String
}

struct BootResponse: Codable {
    let peerId: NodeId
    let sessionId: NodeId
    let joinedChannels: [NodeId]
    let errors: [BootError]
    let pendingMessages: [CoordMessage]
    let blackboardSnapshot: [BlackboardEntry]

    enum CodingKeys: String, CodingKey {
        case peerId = "peer_id"
        case sessionId = "session_id"
        case joinedChannels = "joined_channels"
        case errors
        case pendingMessages = "pending_messages"
        case blackboardSnapshot = "blackboard_snapshot"
    }
}

// MARK: - Health

struct HealthReport: Codable {
    let overall: String
    let uptimeSecs: Double?

    enum CodingKeys: String, CodingKey {
        case overall
        case uptimeSecs = "uptime_secs"
    }

    var isHealthy: Bool {
        overall == "Healthy"
    }
}

// MARK: - SSE

struct CoordSseEvent: Codable {
    let type: String
    let from: String?
    let to: String?
    let channel: String?
    let content: String?
    let messageId: UInt64?
    let key: String?
    let value: String?
    let setBy: String?
    let timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case type, from, to, channel, content, key, value, timestamp
        case messageId = "message_id"
        case setBy = "set_by"
    }

    var isPeerMessage: Bool { type == "peer_message" }
    var isChannelMessage: Bool { type == "channel_message" }
    var isBlackboardUpdate: Bool { type == "blackboard_update" }
}

// MARK: - Time Formatting

enum TimeFormat {
    static func fromUnixMs(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        return formatter.string(from: date)
    }

    static func fromUnixSeconds(_ seconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        return formatter.string(from: date)
    }

    static func relative(fromUnixMs ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d" }
        return formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Peer Deduplication

extension Array where Element == Peer {
    /// Collapse multiple sessions per agent_name — keep the best status + richest summary.
    func deduplicatedByAgent() -> [Peer] {
        var best: [String: Peer] = [:]
        for peer in self {
            if let existing = best[peer.agentName] {
                if peer.status.rank < existing.status.rank ||
                    (peer.status.rank == existing.status.rank &&
                     (peer.summary?.count ?? 0) > (existing.summary?.count ?? 0)) {
                    best[peer.agentName] = peer
                }
            } else {
                best[peer.agentName] = peer
            }
        }
        return Array(best.values)
    }
}

extension PeerStatus {
    var rank: Int {
        switch self {
        case .active: return 0
        case .thinking: return 1
        case .idle: return 2
        case .stale: return 3
        case .offline: return 4
        }
    }
}