import Foundation

// MARK: - Active @-query detection

struct MentionActiveQuery: Equatable {
    let partial: String
    let replaceRange: Range<String.Index>
}

enum AgentMentionAutocomplete {
    /// Returns the in-progress `@agent` fragment at the end of `text`, if any.
    static func activeQuery(in text: String) -> MentionActiveQuery? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        let afterAt = text.index(after: atIndex)
        guard afterAt <= text.endIndex else { return nil }

        let fragment = String(text[afterAt...])
        if fragment.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return nil
        }

        if !fragment.isEmpty,
           fragment.range(of: #"^[a-zA-Z][a-zA-Z0-9-]*$"#, options: .regularExpression) == nil {
            return nil
        }

        return MentionActiveQuery(partial: fragment, replaceRange: atIndex..<text.endIndex)
    }

    static func filteredCandidates(query: String, from agents: [String]) -> [String] {
        let needle = query.lowercased()
        return agents
            .filter { agent in
                if needle.isEmpty { return true }
                return agent.lowercased().hasPrefix(needle)
                    || displayLabel(for: agent).lowercased().contains(needle)
            }
            .sorted()
    }

    static func complete(text: String, query: MentionActiveQuery, agentName: String) -> String {
        var updated = text
        updated.replaceSubrange(query.replaceRange, with: "@\(agentName) ")
        return updated
    }

    static func insertMention(into text: String, agentName: String) -> String {
        if text.isEmpty || text.last?.isWhitespace == true || text.last?.isNewline == true {
            return text + "@\(agentName) "
        }
        return text + " @\(agentName) "
    }

    static func displayLabel(for agentName: String) -> String {
        agentName.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Agent name from messages

enum MessageAgentResolver {
    @MainActor
    static func agentName(
        for message: CoordMessage,
        rosterAgents: [String] = []
    ) -> String? {
        let enriched = PeerNameResolver.shared.enrich(message)
        if let name = enriched.fromAgentName, !name.isEmpty {
            return name
        }
        if let from = enriched.from,
           let name = PeerNameResolver.shared.agentName(forSession: from) {
            return name
        }
        if let signature = inferAuthorFromSignature(in: message.content, rosterAgents: rosterAgents) {
            return signature
        }
        return nil
    }

    /// Who should receive a reply — uses validated principal context from boot.
    @MainActor
    static func replyTarget(
        for message: CoordMessage,
        rosterAgents: [String],
        localAgent: String = PrincipalContext.shared.localAgentName
    ) -> String? {
        let principal = PrincipalContext.shared
        var author = agentName(for: message, rosterAgents: rosterAgents)

        if author == nil, principal.isConfigured, principal.ownsSession(message.from) {
            author = principal.agentName
        }

        let addressee = inferLeadingAddressee(in: message.content, rosterAgents: rosterAgents)
        let mention = firstMention(in: message.content, excluding: localAgent)

        if let author, author != localAgent {
            return author
        }
        if let addressee, addressee != localAgent {
            return addressee
        }
        if let mention {
            return mention
        }
        return author ?? addressee
    }

    /// DM target for a reply — guaranteed when principal is configured and content names an addressee.
    @MainActor
    static func replyDMTarget(
        for message: CoordMessage,
        rosterAgents: [String]
    ) -> String? {
        let local = PrincipalContext.shared.localAgentName
        if let target = replyTarget(for: message, rosterAgents: rosterAgents, localAgent: local),
           target != local {
            return target
        }
        return nil
    }

    /// `Zahra —` / `@zahra-ghorbani —` opener common in fleet channel posts.
    static func inferLeadingAddressee(in content: String, rosterAgents: [String]) -> String? {
        let body = ReplyContext.stripNestedQuotes(from: content)
        guard !body.isEmpty else { return nil }

        for agent in rosterAgents.sorted(by: { $0.count > $1.count }) {
            let label = AgentMentionAutocomplete.displayLabel(for: agent)
            for separator in [" — ", " - ", " —", " -"] {
                if body.hasPrefix("\(label)\(separator)") || body.hasPrefix("@\(agent)\(separator)") {
                    return agent
                }
            }
        }

        let slugPattern = #"^@?([a-zA-Z][a-zA-Z0-9-]*)\s*[—\-]\s*"#
        if let regex = try? NSRegularExpression(pattern: slugPattern),
           let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 1), in: body) {
            return matchRosterAgent(String(body[range]), rosterAgents: rosterAgents)
        }
        return nil
    }

    static func firstMention(in content: String, excluding localAgent: String) -> String? {
        for segment in MentionParser.segments(in: content) {
            if case .mention(let text) = segment {
                let slug = String(text.dropFirst())
                if slug != localAgent { return slug }
            }
        }
        return nil
    }

    /// Match `— Zahra` / `— zahra-ghorbani` closing signatures common in fleet messages.
    static func inferAuthorFromSignature(in content: String, rosterAgents: [String]) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last else { return nil }
        let trimmed = last.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("—") || trimmed.hasPrefix("-") else { return nil }
        var token = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        if token.hasPrefix("@") {
            token = String(token.dropFirst())
        }
        guard !token.isEmpty else { return nil }
        return matchRosterAgent(token, rosterAgents: rosterAgents)
    }

    static func matchRosterAgent(_ token: String, rosterAgents: [String]) -> String? {
        let needle = token.lowercased()
        if let exact = rosterAgents.first(where: { $0.lowercased() == needle }) {
            return exact
        }
        if let label = rosterAgents.first(where: {
            AgentMentionAutocomplete.displayLabel(for: $0).lowercased() == needle
        }) {
            return label
        }
        let firstNameHits = rosterAgents.filter { agent in
            let parts = agent.lowercased().split(separator: "-")
            guard let first = parts.first else { return false }
            return first == needle || needle == first
        }
        if firstNameHits.count == 1 {
            return firstNameHits[0]
        }
        return nil
    }
}