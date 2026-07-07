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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "text": self = .text
        case "query": self = .query
        case "response": self = .response
        case "handoff": self = .handoff
        case "broadcast": self = .broadcast
        default: self = .text
        }
    }
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
    /// Truncated inbox-style body — never raw `msg/id` metadata.
    let lastContent: String
    let lastFrom: String
    let lastTimestamp: Int64
    let isOutbound: Bool

    /// List row subtitle: `sender: preview…` or `You: preview…`
    var previewLine: String {
        guard !lastContent.isEmpty else { return "" }
        if isOutbound {
            return "You: \(lastContent)"
        }
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
        if toAgentName != nil {
            return false
        }
        if let from = fromAgentName {
            if from == localAgent { return false }
            return from == peerAgentName
        }
        // REST-polled inbound DMs: sender session id in `from`, no agent name yet.
        return from != nil
    }

    /// User-visible body with reply/quote metadata stripped (Slack-style).
    var readableBody: String {
        ReplyContext.stripNestedQuotes(from: content)
    }

    var hasDisplayableContent: Bool {
        !readableBody.isEmpty || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasReadableBody: Bool {
        !readableBody.isEmpty
    }

    /// Inbox row / notification preview — never raw `msg/id` metadata.
    var inboxPreview: String {
        if !readableBody.isEmpty {
            return ReplyContext.truncate(readableBody, maxLength: 120)
        }
        if let quoted = extractQuotedSnippet() {
            return ReplyContext.truncate(quoted, maxLength: 120)
        }
        return ""
    }

    private func extractQuotedSnippet() -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { continue }
            let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }
            let lowered = body.lowercased()
            if lowered.hasPrefix("replying to msg/")
                || lowered.hasPrefix("scope:")
                || lowered.hasPrefix("from @")
                || lowered.hasPrefix("in #") {
                continue
            }
            return body
        }
        return nil
    }

    func with(
        id: NodeId? = nil,
        content: String? = nil,
        fromAgentName: String? = nil,
        toAgentName: String? = nil,
        sentAtUnixMs: Int64? = nil
    ) -> CoordMessage {
        CoordMessage(
            id: id ?? self.id,
            from: from,
            channel: channel,
            dmTo: dmTo,
            content: content ?? self.content,
            messageType: messageType,
            replyTo: replyTo,
            sentAtUnixMs: sentAtUnixMs ?? self.sentAtUnixMs,
            pinned: pinned,
            fromAgentName: fromAgentName ?? self.fromAgentName,
            toAgentName: toAgentName ?? self.toAgentName
        )
    }

    func isFromLocalAgent(_ localAgent: String) -> Bool {
        fromAgentName == localAgent || toAgentName != nil
    }

    var fromNodeId: String {
        from.map(String.init) ?? "unknown"
    }

    var sentAtDisplay: String {
        if sentAtUnixMs > 0 {
            return TimeFormat.listTimestamp(fromUnixMs: sentAtUnixMs)
        }
        return ""
    }

    /// Full date + time for message bubbles (e.g. "Jul 3, 2026 at 2:45 PM").
    var sentAtFullDisplay: String {
        if sentAtUnixMs > 0 {
            return TimeFormat.messageTimestamp(fromUnixMs: sentAtUnixMs)
        }
        return ""
    }

    /// Channel name embedded in a quoted DM reply block, if present.
    var embeddedChannelReference: String? {
        ReplyContext.extractChannelReference(from: content)
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
    /// Compact stamp for list rows — today shows time only; older messages show date + time.
    static func listTimestamp(fromUnixMs ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        if Calendar.current.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday \(timeFormatter.string(from: date))"
        }
        return shortDateTimeFormatter.string(from: date)
    }

    /// Full stamp for message bubbles.
    static func messageTimestamp(fromUnixMs ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        if Calendar.current.isDateInToday(date) {
            return "Today at \(timeFormatter.string(from: date))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday at \(timeFormatter.string(from: date))"
        }
        return fullDateTimeFormatter.string(from: date)
    }

    static func fromUnixMs(_ ms: Int64) -> String {
        listTimestamp(fromUnixMs: ms)
    }

    static func fromUnixSeconds(_ seconds: Int64) -> String {
        messageTimestamp(fromUnixMs: seconds * 1000)
    }

    static func relative(fromUnixMs ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d" }
        return shortDateTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let fullDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
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