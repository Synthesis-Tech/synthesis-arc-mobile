import Foundation

/// In-memory hot coordination layer — REST poll primary path when SSE is slow or unavailable.
///
/// forge-graphd's graph is the durable layer; this keeps the UI fresh via poll + refresh
/// without waiting on SSE. SSE remains a best-effort accelerator when it connects.
@MainActor
final class CoordinationHotLayer: ObservableObject {
    static let shared = CoordinationHotLayer()

    @Published private(set) var isRunning = false
    @Published private(set) var lastPollAt: Date?
    @Published private(set) var lastPollDurationMs: Int = 0
    @Published private(set) var pollCount: Int = 0
    @Published private(set) var lastError: String?

    private var pollTask: Task<Void, Never>?
    private weak var fleetService: FleetService?
    private weak var dmService: DMService?
    private weak var channelService: ChannelService?
    private weak var streamService: CoordinationStreamService?

    private let intervalLiveSSE: TimeInterval = 45
    private let intervalRESTOnly: TimeInterval = 10

    private init() {}

    var statusLabel: String {
        guard isRunning else { return "Hot layer idle" }
        if let lastPollAt {
            let ago = Int(Date().timeIntervalSince(lastPollAt))
            return "REST poll active · last \(ago)s ago · \(pollCount) ticks"
        }
        return "REST poll starting"
    }

    func start(
        fleetService: FleetService,
        dmService: DMService,
        channelService: ChannelService,
        streamService: CoordinationStreamService
    ) {
        self.fleetService = fleetService
        self.dmService = dmService
        self.channelService = channelService
        self.streamService = streamService

        pollTask?.cancel()
        isRunning = true
        CoordinationAuditLog.shared.log("Hot layer started — REST poll primary", category: .network)

        pollTask = Task { [weak self] in
            await self?.tick()
            while !Task.isCancelled {
                guard let self else { break }
                let interval = (self.streamService?.isConnected == true)
                    ? self.intervalLiveSSE
                    : self.intervalRESTOnly
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.tick()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
    }

    /// One coordination sweep — inbox, fleet/blackboard, active channel thread.
    func tick() async {
        guard let fleetService, let dmService, let channelService else { return }
        let started = Date()
        lastError = nil

        await dmService.pollInbox()
        await fleetService.refresh()
        // Channel history loads only when a thread is opened — polling here caused UI stalls.

        lastPollAt = Date()
        lastPollDurationMs = Int(Date().timeIntervalSince(started) * 1000)
        pollCount += 1

        if let err = fleetService.error {
            lastError = err
            CoordinationAuditLog.shared.log(
                "Hot layer tick \(pollCount) — fleet error: \(err)",
                category: .network,
                level: .warn
            )
        } else if pollCount == 1 || pollCount % 6 == 0 {
            CoordinationAuditLog.shared.log(
                "Hot layer tick \(pollCount) OK in \(lastPollDurationMs)ms",
                category: .network
            )
        }
    }
}