import SwiftUI

@main
struct SynthesisArcApp: App {
    @StateObject private var fleetService = FleetService()
    @StateObject private var channelService = ChannelService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fleetService)
                .environmentObject(channelService)
        }
        #if os(macOS)
        MenuBarExtra("Fleet", systemImage: "circle.grid.3x3.fill") {
            MenuBarView()
                .environmentObject(fleetService)
        }
        #endif
    }
}
