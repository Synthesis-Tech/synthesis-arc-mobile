import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fleetService: FleetService

    var body: some View {
        TabView {
            FleetView()
                .tabItem {
                    Label("Fleet", systemImage: "circle.grid.3x3.fill")
                }

            ChannelsView()
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
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        #endif
    }
}
