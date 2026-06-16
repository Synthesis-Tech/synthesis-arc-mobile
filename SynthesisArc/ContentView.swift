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

struct ContentView: View {
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var channelService: ChannelService

    var body: some View {
        TabView {
            FleetView()
                .modifier(FleetTabBadge(count: fleetService.exceptionCount))
                .tabItem {
                    Label("Fleet", systemImage: "circle.grid.3x3.fill")
                }

            InboxView()
                .badge(streamService.unreadCount)
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }

            ChannelsView()
                .badge(channelService.totalChannelUnread)
                .tabItem {
                    Label("Channels", systemImage: "bubble.left.and.bubble.right.fill")
                }

            BlackboardView()
                .tabItem {
                    Label("Blackboard", systemImage: "list.clipboard.fill")
                }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .overlay(alignment: .top) {
            ConnectionStatusBar()
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        #endif
    }
}
