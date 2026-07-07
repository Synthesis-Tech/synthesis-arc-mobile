import SwiftUI

enum RecentConversationDisplay {
    static func displayName(for agentName: String) -> String {
        agentName.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

struct RecentConversationRow: View {
    let summary: RecentConversationSummary
    var unreadCount: Int = 0

    private var isUnread: Bool { unreadCount > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentAvatarView(agentName: summary.peerAgentName, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(RecentConversationDisplay.displayName(for: summary.peerAgentName))
                        .font(isUnread ? .subheadline.bold() : .subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if summary.lastMessageIsOutbound {
                        Text("You")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 8)

                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    } else if !summary.latestMessage.sentAtDisplay.isEmpty {
                        Text(summary.latestMessage.sentAtDisplay)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(previewText)
                    .font(.callout)
                    .fontWeight(isUnread ? .medium : .regular)
                    .lineLimit(2)
                    .foregroundStyle(previewForeground)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    private var previewForeground: Color {
        if summary.messageCount == 0 || previewText == "Tap to view message" {
            return Color.secondary.opacity(0.75)
        }
        return isUnread ? .primary : .secondary
    }

    private var previewText: String {
        let preview = summary.latestMessage.inboxPreview
        if !preview.isEmpty {
            if summary.lastMessageIsOutbound, summary.messageCount > 0 {
                return "You: \(preview)"
            }
            return preview
        }
        if summary.messageCount == 0 {
            return "No messages yet"
        }
        if summary.latestMessage.hasDisplayableContent {
            return ReplyContext.truncate(summary.latestMessage.content, maxLength: 120)
        }
        return "Loading message…"
    }
}