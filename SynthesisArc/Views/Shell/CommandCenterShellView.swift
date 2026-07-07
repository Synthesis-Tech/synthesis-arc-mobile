import SwiftUI

/// iPad landscape-first 3-column command center shell.
struct CommandCenterShellView: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var channelService: ChannelService
    @State private var columnVisibility: NavigationSplitViewVisibility = E2EMode.isActive ? .all : .automatic

    var body: some View {
        VStack(spacing: 0) {
            CommandRailMetricsBar()
            Divider()

            NavigationSplitView(columnVisibility: $columnVisibility) {
                CommandRailSidebar()
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
            } content: {
                centerColumn
                    .navigationSplitViewColumnWidth(min: 360, ideal: 480)
            } detail: {
                detailColumn
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .onAppear {
            if E2EMode.isActive {
                columnVisibility = .all
            }
        }
        .overlay(alignment: .top) {
            ConnectionStatusBar()
                .padding(.top, 44)
        }
        .onChange(of: commandCenterState.selectedDestination) { _, destination in
            syncActiveChannel(for: destination)
        }
        .onChange(of: commandCenterState.selectedChannelName) { _, _ in
            syncActiveChannel(for: commandCenterState.selectedDestination)
        }
        .onChange(of: commandCenterState.deepLinkEpoch) { _, _ in
            syncActiveChannel(for: commandCenterState.selectedDestination)
        }
    }

    private func syncActiveChannel(for destination: CommandDestination) {
        if destination == .channels, let name = commandCenterState.selectedChannelName {
            channelService.setActiveChannel(name)
        } else if destination != .channels {
            channelService.setActiveChannel(nil)
        }
    }

    @ViewBuilder
    private var centerColumn: some View {
        switch commandCenterState.selectedDestination {
        case .fleet:
            FleetCommandCenterView()
        case .inbox:
            InboxCommandCenterView()
        case .channels:
            ChannelsCommandCenterView()
        case .director:
            DirectorCommandCenterView()
        case .blackboard:
            BlackboardCommandCenterView()
        case .settings:
            SettingsConnectionFormView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch commandCenterState.selectedDestination {
        case .fleet:
            FleetInspectorPane()
        case .inbox:
            InboxInspectorPane()
        case .channels:
            ChannelsInspectorPane()
        case .director:
            DirectorInspectorPane()
        case .blackboard:
            BlackboardInspectorPane()
        case .settings:
            SettingsPreferencesPane()
        }
    }
}