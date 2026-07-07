import SwiftUI

/// Inbox list column — selection drives DM thread in the inspector column.
struct InboxCommandCenterView: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var fleetService: FleetService
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
        Group {
            if isLoading && !hasInboxContent {
                ProgressView("Loading inbox...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, !hasInboxContent {
                ContentUnavailableView {
                    Label("Inbox Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadInbox() } }
                }
            } else if !hasInboxContent {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "tray",
                    description: Text(streamService.isConnected
                        ? "Waiting for fleet DMs..."
                        : "DMs appear when forge-graphd is reachable")
                )
            } else {
                List(conversations, selection: inboxSelection) { conversation in
                    RecentConversationRow(
                        summary: conversation,
                        unreadCount: dmService.unreadCount(from: conversation.peerAgentName)
                    )
                    .tag(conversation.peerAgentName)
                    .listRowBackground(
                        commandCenterState.selectedInboxSender == conversation.peerAgentName
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { Task { await loadInbox() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await loadInbox() }
        .refreshable { await loadInbox() }
    }

    private var inboxSelection: Binding<String?> {
        Binding(
            get: { commandCenterState.selectedInboxSender },
            set: { sender in
                commandCenterState.selectInboxSender(sender)
                if let sender {
                    Task {
                        await dmService.markConversationDelivered(sender: sender)
                        await dmService.hydrateThreadContent(for: sender)
                    }
                }
            }
        )
    }

    private func loadInbox() async {
        isLoading = true
        error = nil
        do {
            let polled = try await client.pollMessages()
            streamService.seedInbox(polled)
            await dmService.hydrateAllEmptyMessages()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// Inbox detail column — inline DM (no sheet on iPad).
struct InboxInspectorPane: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var dmService: DMService

    var body: some View {
        Group {
            if let sender = commandCenterState.selectedInboxSender {
                DMView(
                    peer: peer(for: sender),
                    draftKeyOverride: ComposerDraftStore.inboxKey(sender)
                )
                .id(sender)
                .task(id: sender) {
                    await dmService.markConversationDelivered(sender: sender)
                    await dmService.hydrateThreadContent(for: sender)
                }
            } else {
                ContentUnavailableView(
                    "Select a Conversation",
                    systemImage: "tray",
                    description: Text("Choose a sender to read and reply inline.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}