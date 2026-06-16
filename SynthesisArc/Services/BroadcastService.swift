import Foundation

/// Director broadcasts — channel sends via forge-graphd
@MainActor
final class BroadcastService: ObservableObject {
    @Published var error: String?
    @Published var lastResult: String?

    private var client: ForgeGraphClient

    init() {
        client = AppConfig.shared.makeClient()
    }

    func reloadClient() {
        client = AppConfig.shared.makeClient()
    }

    /// Send a single channel message.
    func broadcast(channel: String, content: String) async throws {
        reloadClient()
        error = nil
        try await client.sendChannelMessage(channel: channel, content: content)
    }

    /// Fan-out to default watchlist channels (#engineering, #ops).
    func broadcastToWatchlistChannels(content: String) async throws {
        var failures: [String] = []
        for channel in ChannelWatchlist.defaultChannels.sorted() {
            do {
                try await broadcast(channel: channel, content: content)
            } catch {
                failures.append("#\(channel): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw BroadcastError.partialFailure(failures)
        }
    }
}

enum BroadcastError: Error, LocalizedError {
    case partialFailure([String])

    var errorDescription: String? {
        switch self {
        case .partialFailure(let details):
            return details.joined(separator: "; ")
        }
    }
}