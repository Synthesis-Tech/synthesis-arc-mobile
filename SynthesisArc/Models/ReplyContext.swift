import Foundation

/// Context carried when replying to an existing coordination message.
struct ReplyContext: Equatable {
    let messageId: UInt64
    let channelName: String?
    let senderAgentName: String?
    let contentPreview: String

    /// Build reply context for a bilateral DM thread (quote msg/id + optional channel scope).
    @MainActor
    static func fromDM(message: CoordMessage, peerAgentName: String) -> ReplyContext {
        let enriched = PeerNameResolver.shared.enrich(message)
        return ReplyContext(
            messageId: enriched.id,
            channelName: extractChannelReference(from: enriched.content),
            senderAgentName: peerAgentName,
            contentPreview: enriched.content
        )
    }

    /// Parse `> in #channel` lines from quoted DM blocks.
    static func extractChannelReference(from content: String) -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> in #") {
                let name = String(trimmed.dropFirst("> in #".count)).trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    @MainActor
    static func from(
        message: CoordMessage,
        channel: String?,
        rosterAgents: [String] = [],
        localAgent: String = PrincipalContext.shared.localAgentName
    ) -> ReplyContext {
        ReplyContext(
            messageId: message.id,
            channelName: channel,
            senderAgentName: MessageAgentResolver.replyDMTarget(
                for: PeerNameResolver.shared.enrich(message),
                rosterAgents: rosterAgents
            ),
            contentPreview: message.content
        )
    }

    /// Body text with nested quote / reply blocks removed — scopes to this message only.
    var strippedBody: String {
        Self.stripNestedQuotes(from: contentPreview)
    }

    var truncatedPreview: String {
        Self.truncate(strippedBody, maxLength: 80)
    }

    /// One-line preview for the compact reply bar.
    var compactPreview: String {
        Self.truncate(strippedBody, maxLength: 52)
    }

    /// Short ref for tight UI — full id remains in `referenceTag` for copy/send.
    var compactReference: String {
        let id = String(messageId)
        if id.count > 8 {
            return "…\(id.suffix(6))"
        }
        return id
    }

    var senderLabel: String {
        guard let senderAgentName else { return "unknown" }
        return AgentMentionAutocomplete.displayLabel(for: senderAgentName)
    }

    /// First-name label for the compact reply chrome.
    var compactSenderLabel: String {
        guard let senderAgentName else { return "unknown" }
        let slug = senderAgentName.split(separator: "-").first.map(String.init) ?? senderAgentName
        return slug.prefix(1).uppercased() + slug.dropFirst()
    }

    var deliveryLabel: String {
        prefersDirectMessage ? "DM" : "Channel"
    }

    /// Machine-readable ref agents can grep in DMs (no `reply_to` on the DM API).
    var referenceTag: String {
        "msg/\(messageId)"
    }

    /// Quoted block prepended to outbound DMs opened from a channel message.
    var dmQuotePrefix: String {
        var lines = [
            "> replying to \(referenceTag)",
            "> scope: this message only — not the full channel thread",
        ]
        if let senderAgentName {
            lines.append("> from @\(senderAgentName)")
        }
        if let channelName {
            lines.append("> in #\(channelName)")
        }
        if !truncatedPreview.isEmpty {
            lines.append("> \(truncatedPreview)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Targeted replies should use DM delivery (peer_message tier) so only this agent is notified.
    var prefersDirectMessage: Bool {
        guard let senderAgentName else { return false }
        return !senderAgentName.isEmpty
    }

    /// One-line ref agents can grep when `reply_to` is set on channel sends.
    var channelReplyHeader: String {
        var parts = ["↩ \(referenceTag)"]
        if let senderAgentName {
            parts.append("@\(senderAgentName)")
        }
        if !truncatedPreview.isEmpty {
            parts.append("\"\(truncatedPreview)\"")
        }
        return parts.joined(separator: " ")
    }

    /// Strip nested `>` / `↩` quote lines so replies don't re-embed an entire thread.
    static func stripNestedQuotes(from content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let nonQuote = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            if trimmed.hasPrefix(">") { return false }
            if trimmed.hasPrefix("↩") { return false }
            if trimmed.lowercased().hasPrefix("replying to msg/") { return false }
            if trimmed.lowercased().hasPrefix("scope:") { return false }
            return true
        }
        return nonQuote
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func truncate(_ text: String, maxLength: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }
}