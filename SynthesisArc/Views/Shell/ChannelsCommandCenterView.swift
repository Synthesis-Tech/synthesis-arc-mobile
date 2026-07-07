import SwiftUI

/// Channels list column — selection drives thread in the inspector column.
struct ChannelsCommandCenterView: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var channelService: ChannelService
    @State private var searchText = ""
    @State private var showCreateChannel = false
    @State private var channelToOpenAfterCreate: String?

    private var filteredChannels: [Channel] {
        if searchText.isEmpty {
            return channelService.channels
        }
        return channelService.channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(searchText) ||
            (channel.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            channelSearchBar
            Divider()

            Group {
                if channelService.channels.isEmpty && !channelService.isLoading {
                    ContentUnavailableView(
                        "No Channels",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Channels appear when forge-graphd is reachable.")
                    )
                } else if filteredChannels.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search
                } else {
                    List(filteredChannels) { channel in
                        Button {
                            commandCenterState.selectChannel(channel.name)
                            channelService.setActiveChannel(channel.name)
                        } label: {
                            ChannelRow(channel: channel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(E2EAccessibility.channelRow(channel.name))
                        .accessibilityAddTraits(.isButton)
                        .listRowBackground(
                            commandCenterState.selectedChannelName == channel.name
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .accessibilityIdentifier(E2EAccessibility.channelsList)
        }
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateChannel = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create channel")
                .accessibilityIdentifier(E2EAccessibility.channelsCreate)
            }
        }
        .sheet(isPresented: $showCreateChannel, onDismiss: openChannelAfterCreateIfNeeded) {
            CreateChannelSheet { name in
                channelToOpenAfterCreate = name
            }
        }
        .task { await channelService.loadChannels() }
        .refreshable { await channelService.loadChannels() }
    }

    private var channelSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search channels", text: $searchText)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(searchFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func openChannelAfterCreateIfNeeded() {
        guard let name = channelToOpenAfterCreate else { return }
        channelToOpenAfterCreate = nil
        commandCenterState.selectChannel(name)
    }

    private var searchFieldBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.systemGray6)
        #endif
    }
}

/// Channels detail column — inline thread or inline DM (no sheet on iPad).
struct ChannelsInspectorPane: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var fleetService: FleetService

    private var selectedChannel: Channel? {
        guard let name = commandCenterState.selectedChannelName else { return nil }
        if let channel = channelService.resolvedChannel(named: name) {
            return channel
        }
        return Channel(
            nodeId: 0,
            name: name,
            description: nil,
            visibility: channelService.resolvedVisibility(for: name),
            memberCount: 0
        )
    }

    var body: some View {
        Group {
            if let channel = selectedChannel {
                switch commandCenterState.channelInspectorMode {
                case .thread:
                    ChannelThreadView(channel: channel) { peer, replyContext in
                        commandCenterState.openChannelDM(
                            agentName: peer.agentName,
                            replyContext: replyContext
                        )
                    }
                    .id(channel.name)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(E2EAccessibility.channelThread)
                case .dm(let agentName):
                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                commandCenterState.showChannelThread()
                            } label: {
                                Label("Back to #\(channel.name)", systemImage: "chevron.left")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider()
                        DMView(
                            peer: peer(for: agentName),
                            replyContext: commandCenterState.channelDMReplyContext,
                            draftKeyOverride: ComposerDraftStore.channelDMKey(
                                channel: channel.name,
                                agent: agentName
                            )
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Channel",
                    systemImage: "number",
                    description: Text("Choose a channel to read and post inline.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: commandCenterState.selectedChannelName) {
            guard let name = commandCenterState.selectedChannelName else { return }
            channelService.setActiveChannel(name)
        }
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