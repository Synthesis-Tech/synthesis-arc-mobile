import Foundation

/// Context carried when replying to an existing coordination message.
struct ReplyContext: Equatable {
    let messageId: UInt64
    let channelName: String?
    let senderAgentName: String?
    let contentPreview: String

    @MainActor
    static func from(message: CoordMessage, channel: String?) -> ReplyContext {
        ReplyContext(
            messageId: message.id,
            channelName: channel,
            senderAgentName: MessageAgentResolver.agentName(for: message),
            contentPreview: message.content
        )
    }

    var truncatedPreview: String {
        let maxLength = 140
        let collapsed = contentPreview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }

    var senderLabel: String {
        guard let senderAgentName else { return "unknown" }
        return AgentMentionAutocomplete.displayLabel(for: senderAgentName)
    }

    /// Machine-readable ref agents can grep in DMs (no `reply_to` on the DM API).
    var referenceTag: String {
        "msg/\(messageId)"
    }

    /// Quoted block prepended to outbound DMs opened from a channel message.
    var dmQuotePrefix: String {
        var lines = ["> replying to \(referenceTag)"]
        if let senderAgentName {
            lines.append("> from @\(senderAgentName)")
        }
        if let channelName {
            lines.append("> in #\(channelName)")
        }
        lines.append("> \(truncatedPreview)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}