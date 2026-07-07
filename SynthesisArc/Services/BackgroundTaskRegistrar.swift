import Foundation

#if os(iOS)
import BackgroundTasks

/// Registers BGAppRefresh for coordination poll when iOS suspends the app.
@MainActor
enum BackgroundTaskRegistrar {
    static let refreshIdentifier = "com.synthesisarc.coordination-refresh"

    private static weak var fleetService: FleetService?
    private static weak var dmService: DMService?
    private static weak var channelService: ChannelService?

    static func register(
        fleetService: FleetService,
        dmService: DMService,
        channelService: ChannelService
    ) {
        Self.fleetService = fleetService
        Self.dmService = dmService
        Self.channelService = channelService

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handleRefresh(refresh)
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) async {
        let work = Task {
            await dmService?.pollInbox()
            await fleetService?.refresh()
            await channelService?.loadChannels()
        }
        task.expirationHandler = { work.cancel() }
        await work.value
        scheduleRefresh()
        task.setTaskCompleted(success: !work.isCancelled)
    }
}
#else
@MainActor
enum BackgroundTaskRegistrar {
    static func register(
        fleetService: FleetService,
        dmService: DMService,
        channelService: ChannelService
    ) {}

    static func scheduleRefresh() {}
}
#endif