import Foundation
import Combine

/// Coordinates channel data from daemon
@MainActor
class ChannelService: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var messages: [String: [ChannelMessage]] = [:]
    @Published var totalCounts: [String: Int64] = [:]
    @Published var isLoading = false
    @Published var error: String?

    private var daemon: DaemonClient

    init() {
        let config = AppConfig.shared
        self.daemon = DaemonClient(host: config.daemonHost, port: config.daemonPort)
    }

    func loadChannels() async {
        isLoading = true
        do {
            channels = try await daemon.listChannels()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadHistory(channel: String, limit: Int = 50) async {
        do {
            let response = try await daemon.channelHistory(name: channel, limit: limit)
            messages[channel] = response.messages
            totalCounts[channel] = response.totalCount
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(channel: String, fromId: String, content: String) async {
        do {
            try await daemon.sendChannelMessage(
                channel: channel,
                fromId: fromId,
                content: content
            )
            // Reload history after sending
            await loadHistory(channel: channel)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
