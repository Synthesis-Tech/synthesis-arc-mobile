import SwiftUI

@main
struct SynthesisArcApp: App {
    @StateObject private var fleetService = FleetService()
    @StateObject private var channelService = ChannelService()
    @StateObject private var dmService = DMService()
    @StateObject private var streamService = CoordinationStreamService()
    @StateObject private var nameResolver = PeerNameResolver.shared
    @StateObject private var pushService = PushNotificationService.shared
    @StateObject private var appLifecycle = AppLifecycle.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fleetService)
                .environmentObject(channelService)
                .environmentObject(dmService)
                .environmentObject(streamService)
                .environmentObject(pushService)
                .trackScenePhase(lifecycle: appLifecycle)
                .task {
                    streamService.fleetService = fleetService
                    streamService.channelService = channelService
                    streamService.dmService = dmService
                    fleetService.attachDMService(dmService)
                    fleetService.attachChannelService(channelService)
                    await fleetService.bootAsPeer()
                    await pushService.requestPermissionIfNeeded()
                    await nameResolver.refresh()
                    streamService.start()
                }
        }
        #if os(macOS)
        MenuBarExtra("Fleet", systemImage: "circle.grid.3x3.fill") {
            MenuBarView()
                .environmentObject(fleetService)
                .environmentObject(streamService)
        }
        #endif
    }
}

// MARK: - Scene phase → AppLifecycle

private struct ScenePhaseTracker: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var lifecycle: AppLifecycle

    func body(content: Content) -> some View {
        content
            .onAppear { lifecycle.update(scenePhase: scenePhase) }
            .onChange(of: scenePhase) { _, newPhase in
                lifecycle.update(scenePhase: newPhase)
            }
    }
}

private extension View {
    func trackScenePhase(lifecycle: AppLifecycle) -> some View {
        modifier(ScenePhaseTracker(lifecycle: lifecycle))
    }
}