import Foundation
import Combine

/// Coordinates channel data from forge-graphd
@MainActor
class ChannelService: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var messages: [String: [CoordMessage]] = [:]
    @Published var channelUnread: [String: Int] = [:]
    @Published var channelPreviews: [String: ChannelPreview] = [:]
    @Published var isLoading = false
    @Published var error: String?

    private var client: ForgeGraphClient
    private var activeChannelName: String?

    var totalChannelUnread: Int {
        channelUnread.values.reduce(0, +)
    }

    init() {
        self.client = AppConfig.shared.makeClient()
    }

    func reloadClient() {
        client = AppConfig.shared.makeClient()
    }

    func loadChannels() async {
        isLoading = true
        reloadClient()
        do {
            channels = try await client.listChannels()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadHistory(channel: String, limit: Int = 50) async {
        reloadClient()
        do {
            let history = try await client.channelHistory(name: channel, limit: limit)
            storeMessages(history, for: channel)
            if let last = history.max(by: { $0.sentAtUnixMs < $1.sentAtUnixMs }) {
                updatePreview(channel: channel, message: last)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            print("[ChannelService] loadHistory(\(channel)) failed: \(error)")
        }
    }

    func send(channel: String, content: String, replyTo: NodeId? = nil) async {
        reloadClient()
        do {
            try await client.sendChannelMessage(channel: channel, content: content, replyTo: replyTo)
            await loadHistory(channel: channel)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Append a message received via SSE (deduped by message id).
    func appendLiveMessage(channel: String, message: CoordMessage) {
        var channelMessages = messages[channel] ?? []
        guard !channelMessages.contains(where: { $0.id == message.id }) else { return }
        channelMessages.append(message)
        channelMessages.sort { $0.sentAtUnixMs < $1.sentAtUnixMs }
        storeMessages(channelMessages, for: channel)
        updatePreview(channel: channel, message: message)
        if activeChannelName != channel {
            var unread = channelUnread
            unread[channel, default: 0] += 1
            channelUnread = unread
        }
    }

    func markChannelRead(_ channel: String) {
        var unread = channelUnread
        unread.removeValue(forKey: channel)
        channelUnread = unread
    }

    func setActiveChannel(_ channel: String?) {
        activeChannelName = channel
        if let channel {
            markChannelRead(channel)
        }
    }

    private func updatePreview(channel: String, message: CoordMessage) {
        let from = message.fromAgentName ?? (message.from.map(String.init) ?? "unknown")
        let preview = ChannelPreview(
            lastContent: message.content,
            lastFrom: from,
            lastTimestamp: message.sentAtUnixMs
        )
        if let existing = channelPreviews[channel], existing.lastTimestamp > message.sentAtUnixMs {
            return
        }
        var previews = channelPreviews
        previews[channel] = preview
        channelPreviews = previews
    }

    /// Reassign so `@Published` emits — in-place dictionary mutation does not refresh SwiftUI.
    private func storeMessages(_ channelMessages: [CoordMessage], for channel: String) {
        var updated = messages
        updated[channel] = channelMessages
        messages = updated
    }
}