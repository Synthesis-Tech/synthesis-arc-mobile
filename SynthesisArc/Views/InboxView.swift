import SwiftUI

/// Inbox — inbound DMs grouped by sender (Slack-style DM sidebar)
struct InboxView: View {
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var fleetService: FleetService
    @State private var isLoading = false
    @State private var error: String?

    private var client: ForgeGraphClient {
        AppConfig.shared.makeClient()
    }

    private var conversations: [DMConversationSummary] {
        dmService.conversationSummaries()
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && conversations.isEmpty {
                    ProgressView("Loading inbox...")
                        .padding(.top, 40)
                } else if let error, conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadInbox() } }
                    }
                    .padding(.top, 40)
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "tray",
                        description: Text(streamService.isConnected
                            ? "Waiting for fleet DMs..."
                            : "DMs appear when forge-graphd is reachable")
                    )
                } else {
                    List(conversations) { conversation in
                        NavigationLink {
                            DMView(peer: peer(for: conversation.senderAgentName))
                        } label: {
                            conversationRow(conversation)
                        }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await loadInbox() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadInbox()
            }
            .refreshable {
                await loadInbox()
            }
            .onAppear {
                streamService.markInboxRead()
            }
        }
    }

    private func conversationRow(_ conversation: DMConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayName(for: conversation.senderAgentName))
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                Spacer()
                Text(conversation.latestMessage.sentAtDisplay)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(conversation.latestMessage.content)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if conversation.messageCount > 1 {
                Text("\(conversation.messageCount) messages")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func displayName(for agentName: String) -> String {
        agentName.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func peer(for agentName: String) -> Peer {
        fleetService.peers.first(where: { $0.agentName == agentName })
            ?? Peer(
                agentName: agentName,
                pid: nil,
                cwd: nil,
                gitRoot: nil,
                summary: nil,
                status: .offline
            )
    }

    private func loadInbox() async {
        isLoading = true
        error = nil
        do {
            let polled = try await client.pollMessages()
            streamService.seedInbox(polled)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}