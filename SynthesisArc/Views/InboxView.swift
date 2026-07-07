import SwiftUI

/// Inbox — inbound DMs grouped by sender (Slack-style DM sidebar)
struct InboxView: View {
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var commandCenterState: CommandCenterState
    @State private var navigationPath = NavigationPath()
    @State private var isLoading = false
    @State private var error: String?

    private var client: ForgeGraphClient {
        AppConfig.shared.makeClient()
    }

    private var conversations: [RecentConversationSummary] {
        dmService.unifiedConversations()
    }

    private var hasInboxContent: Bool {
        !conversations.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoading && !hasInboxContent {
                    ProgressView("Loading inbox...")
                        .padding(.top, 40)
                } else if let error, !hasInboxContent {
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
                } else if !hasInboxContent {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "tray",
                        description: Text(streamService.isConnected
                            ? "Waiting for fleet DMs..."
                            : "DMs appear when forge-graphd is reachable")
                    )
                } else {
                    List {
                        ForEach(conversations) { conversation in
                            NavigationLink(value: conversation.peerAgentName) {
                                RecentConversationRow(
                                    summary: conversation,
                                    unreadCount: dmService.unreadCount(from: conversation.peerAgentName)
                                )
                            }
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
            .navigationDestination(for: String.self) { sender in
                DMView(
                    peer: peer(for: sender),
                    draftKeyOverride: ComposerDraftStore.inboxKey(sender)
                )
                .onAppear {
                    Task {
                        await dmService.markConversationDelivered(sender: sender)
                        await dmService.hydrateThreadContent(for: sender)
                    }
                }
            }
            .onChange(of: commandCenterState.deepLinkEpoch) { _, _ in
                openDeepLinkedInboxIfNeeded()
            }
        }
    }

    private func openDeepLinkedInboxIfNeeded() {
        guard commandCenterState.phoneTab == .inbox,
              let sender = commandCenterState.selectedInboxSender else { return }
        navigationPath = NavigationPath([sender])
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
            dmService.seedInbound(polled)
            await dmService.hydrateAllEmptyMessages()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}