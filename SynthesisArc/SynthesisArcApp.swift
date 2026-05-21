import SwiftUI

@main
struct SynthesisArcApp: App {
    @StateObject private var fleetService = FleetService()
    @StateObject private var channelService = ChannelService()
    @StateObject private var nameResolver = PeerNameResolver.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fleetService)
                .environmentObject(channelService)
                .task {
                    // Boot as Daniel's peer — register, join channels, get initial state
                    await fleetService.bootAsPeer()
                    await nameResolver.refresh()
                }
        }
        #if os(macOS)
        MenuBarExtra("Fleet", systemImage: "circle.grid.3x3.fill") {
            MenuBarView()
                .environmentObject(fleetService)
        }
        #endif
    }
}
