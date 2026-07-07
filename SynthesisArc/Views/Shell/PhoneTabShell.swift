import SwiftUI

private struct FleetTabBadge: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        if count > 0 {
            content.badge(count)
        } else {
            content
        }
    }
}

/// iPhone compact shell — 6-tab layout with deep-link tab selection.
struct PhoneTabShell: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var channelService: ChannelService

    var body: some View {
        TabView(selection: $commandCenterState.phoneTab) {
            FleetView()
                .modifier(FleetTabBadge(count: fleetService.exceptionCount))
                .tag(PhoneTab.fleet)
                .tabItem {
                    Label("Fleet", systemImage: "circle.grid.3x3.fill")
                }

            InboxView()
                .badge(dmService.unreadInboundCount)
                .tag(PhoneTab.inbox)
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }

            ChannelsView()
                .badge(channelService.totalChannelUnread)
                .tag(PhoneTab.channels)
                .tabItem {
                    Label("Channels", systemImage: "bubble.left.and.bubble.right.fill")
                }

            DirectorConsoleView()
                .tag(PhoneTab.director)
                .tabItem {
                    Label("Director", systemImage: "bolt.fill")
                }

            BlackboardView()
                .tag(PhoneTab.blackboard)
                .tabItem {
                    Label("Blackboard", systemImage: "list.clipboard.fill")
                }

            NavigationStack {
                SettingsView()
            }
            .tag(PhoneTab.settings)
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .phoneTabBarChrome()
        .overlay(alignment: .top) {
            ConnectionStatusBar()
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        #endif
    }
}