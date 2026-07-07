import Foundation

/// Runs cold-start boot exactly once per process — survives SwiftUI `.task` re-execution.
@MainActor
final class AppLaunchCoordinator {
    static let shared = AppLaunchCoordinator()

    private var launchTask: Task<Void, Never>?

    private init() {}

    func runIfNeeded(
        fleetService: FleetService,
        channelService: ChannelService,
        dmService: DMService,
        streamService: CoordinationStreamService,
        pushService: PushNotificationService,
        nameResolver: PeerNameResolver
    ) {
        guard launchTask == nil else {
            CoordinationAuditLog.shared.log(
                "Launch skipped — boot task already running or finished",
                category: .lifecycle
            )
            return
        }

        streamService.fleetService = fleetService
        streamService.channelService = channelService
        streamService.dmService = dmService
        fleetService.attachDMService(dmService)
        fleetService.attachChannelService(channelService)

        #if os(iOS)
        BackgroundTaskRegistrar.register(
            fleetService: fleetService,
            dmService: dmService,
            channelService: channelService
        )
        #endif

        launchTask = Task {
            CoordinationAuditLog.shared.log("App launch — starting boot", category: .lifecycle)
            fleetService.isBootstrapping = true
            defer { fleetService.isBootstrapping = false }

            await fleetService.bootAsPeer(reason: "cold-launch")

            CoordinationHotLayer.shared.start(
                fleetService: fleetService,
                dmService: dmService,
                channelService: channelService,
                streamService: streamService
            )

            // SSE is best-effort; hot layer + REST setup proceed immediately.
            streamService.start(force: true)
            await fleetService.completeBootSetup()
            await pushService.requestPermissionIfNeeded()
            await nameResolver.refresh()
            await FieldReportUploader.shared.flushPending()
            CoordinationAuditLog.shared.log("Cold launch complete", category: .lifecycle)
        }
    }
}