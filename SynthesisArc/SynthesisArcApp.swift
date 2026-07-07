import SwiftUI
import UserNotifications

@main
struct ForgeCommandApp: App {
    @StateObject private var fleetService = FleetService()
    @StateObject private var channelService = ChannelService()
    @StateObject private var dmService = DMService()
    @StateObject private var streamService = CoordinationStreamService()
    @StateObject private var commandCenterState = CommandCenterState()
    @StateObject private var composerDrafts = ComposerDraftStore()
    @StateObject private var nameResolver = PeerNameResolver.shared
    @StateObject private var pushService = PushNotificationService.shared
    @StateObject private var appLifecycle = AppLifecycle.shared
    private let notificationDelegate = NotificationRoutingDelegate()

    init() {
        let delegate = notificationDelegate
        UNUserNotificationCenter.current().delegate = delegate
        delegate.onRoute = { route in
            DeepLinkCoordinator.shared.enqueue(route)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appTheme()
                .environmentObject(fleetService)
                .environmentObject(channelService)
                .environmentObject(dmService)
                .environmentObject(streamService)
                .environmentObject(commandCenterState)
                .environmentObject(composerDrafts)
                .environmentObject(pushService)
                .trackScenePhase(
                    lifecycle: appLifecycle,
                    fleetService: fleetService,
                    dmService: dmService,
                    channelService: channelService,
                    streamService: streamService
                )
                .onOpenURL { url in
                    if let route = DeepLinkRoute(url: url) {
                        CoordinationAuditLog.shared.log(
                            "URL open → \(route.auditLabel)",
                            category: .lifecycle
                        )
                        DeepLinkCoordinator.shared.enqueue(route)
                    }
                }
                .onAppear {
                    if E2EMode.isActive {
                        AppConfig.shared.applyE2EEnvironment()
                    }
                    AppLaunchCoordinator.shared.runIfNeeded(
                        fleetService: fleetService,
                        channelService: channelService,
                        dmService: dmService,
                        streamService: streamService,
                        pushService: pushService,
                        nameResolver: nameResolver
                    )
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
    let fleetService: FleetService
    let dmService: DMService
    let channelService: ChannelService
    let streamService: CoordinationStreamService

    func body(content: Content) -> some View {
        content
            .onAppear {
                lifecycle.update(scenePhase: scenePhase)
                BackgroundCoordinationService.handleScenePhase(
                    scenePhase,
                    fleetService: fleetService,
                    dmService: dmService,
                    channelService: channelService,
                    streamService: streamService
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                lifecycle.update(scenePhase: newPhase)
                BackgroundCoordinationService.handleScenePhase(
                    newPhase,
                    fleetService: fleetService,
                    dmService: dmService,
                    channelService: channelService,
                    streamService: streamService
                )
            }
    }
}

private extension View {
    func trackScenePhase(
        lifecycle: AppLifecycle,
        fleetService: FleetService,
        dmService: DMService,
        channelService: ChannelService,
        streamService: CoordinationStreamService
    ) -> some View {
        modifier(ScenePhaseTracker(
            lifecycle: lifecycle,
            fleetService: fleetService,
            dmService: dmService,
            channelService: channelService,
            streamService: streamService
        ))
    }
}
