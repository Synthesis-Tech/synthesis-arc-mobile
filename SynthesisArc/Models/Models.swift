import Foundation

// MARK: - Peer ID (wraps a string, matches Rust PeerId(String))

struct PeerId: Codable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Peer Info (matches Rust PeerInfo exactly)

struct Peer: Codable, Identifiable {
    var id: String { peerId.value }
    let peerId: PeerId
    let name: String
    let pid: UInt32
    let cwd: String
    let gitRoot: String?
    let summary: String
    let status: String?
    let registeredAt: String
    let lastSeen: String

    // Enriched client-side from blackboard
    var blackboardStatus: String?
    var bootState: String?

    enum CodingKeys: String, CodingKey {
        case peerId = "id"
        case name, pid, cwd
        case gitRoot = "git_root"
        case summary, status
        case registeredAt = "registered_at"
        case lastSeen = "last_seen"
    }

    /// Status color based on heartbeat recency
    var statusColor: StatusColor {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: lastSeen) else { return .gray }
        let age = Date().timeIntervalSince(date)
        if age < 60 { return .green }
        if age < 300 { return .yellow }
        return .red
    }

    enum StatusColor {
        case green, yellow, red, gray
    }
}

// MARK: - Channel (matches Rust Channel exactly)

struct Channel: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let createdBy: String
    let createdAt: String
    let memberCount: Int
    let visibility: String?

    enum CodingKeys: String, CodingKey {
        case name, description
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberCount = "member_count"
        case visibility
    }
}

// MARK: - Channel Message (matches Rust ChannelMessage exactly)

struct ChannelMessage: Codable, Identifiable {
    let id: Int64
    let channelName: String
    let fromId: String
    let content: String
    let messageType: String?
    let replyTo: Int64?
    let sentAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case channelName = "channel_name"
        case fromId = "from_id"
        case content
        case messageType = "message_type"
        case replyTo = "reply_to"
        case sentAt = "sent_at"
    }
}

// MARK: - Paginated Channel History (matches Rust PaginatedChannelHistory)

struct PaginatedChannelHistory: Codable {
    let messages: [ChannelMessage]
    let totalCount: Int64

    enum CodingKeys: String, CodingKey {
        case messages
        case totalCount = "total_count"
    }
}

// MARK: - Blackboard Entry (matches Rust BlackboardEntry exactly)

struct BlackboardEntry: Codable, Identifiable {
    var id: String { key }
    let key: String
    let value: String
    let setBy: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case key, value
        case setBy = "set_by"
        case updatedAt = "updated_at"
    }
}

// MARK: - Boot Response (matches Rust BootResponse)

struct BootResponse: Codable {
    let peerId: PeerId
    let pendingMessages: [PeerDM]?
    let channelHistory: [String: [ChannelMessage]]?
    let blackboardSnapshot: [BlackboardEntry]?
    let daemonHealthy: Bool

    enum CodingKeys: String, CodingKey {
        case peerId = "peer_id"
        case pendingMessages = "pending_messages"
        case channelHistory = "channel_history"
        case blackboardSnapshot = "blackboard_snapshot"
        case daemonHealthy = "daemon_healthy"
    }
}

// MARK: - SSE Notification (matches Rust SseNotification)

struct SseNotification: Codable {
    let eventType: String
    let from: String
    let content: String
    let messageId: Int64
    let sentAt: String

    enum CodingKeys: String, CodingKey {
        case eventType = "type"
        case from, content
        case messageId = "message_id"
        case sentAt = "sent_at"
    }
}
