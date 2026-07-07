import SwiftUI

/// Keeps coordination fresh across foreground/background transitions.
@MainActor
enum BackgroundCoordinationService {
    private static var wasBackgrounded = false

    static func handleScenePhase(
        _ phase: ScenePhase,
        fleetService: FleetService,
        dmService: DMService,
        channelService: ChannelService,
        streamService: CoordinationStreamService
    ) {
        switch phase {
        case .active:
            CoordinationAuditLog.shared.log("App became active", category: .lifecycle)
            if wasBackgrounded {
                streamService.resumeIfNeeded()
                wasBackgrounded = false
                CoordinationHotLayer.shared.start(
                    fleetService: fleetService,
                    dmService: dmService,
                    channelService: channelService,
                    streamService: streamService
                )
                Task {
                    await CoordinationHotLayer.shared.tick()
                    await channelService.loadChannels()
                    if fleetService.isBooted {
                        await channelService.syncMembership()
                    }
                }
            } else if !fleetService.isBooted {
                CoordinationAuditLog.shared.log(
                    "Foreground refresh deferred — boot in progress",
                    category: .lifecycle
                )
            }
        case .background:
            wasBackgrounded = true
            CoordinationAuditLog.shared.log("App entered background", category: .lifecycle)
            BackgroundTaskRegistrar.scheduleRefresh()
            Task {
                await FieldReportUploader.shared.flushPending()
                await dmService.pollInbox()
                await fleetService.refresh()
            }
        default:
            break
        }
    }
}