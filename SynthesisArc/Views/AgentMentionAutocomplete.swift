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
    static func agentName(for message: CoordMessage) -> String? {
        if let name = message.fromAgentName, !name.isEmpty {
            return name
        }
        if let from = message.from,
           let name = PeerNameResolver.shared.agentName(forSession: from) {
            return name
        }
        return nil
    }
}