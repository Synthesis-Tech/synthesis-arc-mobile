import SwiftUI

/// Channels tab — list of channels with message threads
struct ChannelsView: View {
    @EnvironmentObject var channelService: ChannelService

    var body: some View {
        NavigationStack {
            Group {
                if channelService.channels.isEmpty && !channelService.isLoading {
                    ContentUnavailableView(
                        "No Channels",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Channels will appear when the daemon is reachable.")
                    )
                } else {
                    List(channelService.channels) { channel in
                        NavigationLink(destination: ChannelThreadView(channel: channel)) {
                            ChannelRow(channel: channel)
                        }
                    }
                }
            }
            .navigationTitle("Channels")
            .task {
                await channelService.loadChannels()
            }
            .refreshable {
                await channelService.loadChannels()
            }
        }
    }
}

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Image(systemName: channel.visibility == "private" ? "lock.fill" : "number")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body.bold())
                if !channel.description.isEmpty {
                    Text(channel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(channel.memberCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}

/// Channel thread view — message history + compose
struct ChannelThreadView: View {
    let channel: Channel
    @EnvironmentObject var channelService: ChannelService
    @State private var newMessage = ""

    private var messages: [ChannelMessage] {
        channelService.messages[channel.name] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                    }
                }
                .padding()
            }

            Divider()

            // Compose bar
            HStack(spacing: 8) {
                TextField("Message #\(channel.name)", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif

                Button {
                    guard !newMessage.isEmpty else { return }
                    let text = newMessage
                    newMessage = ""
                    Task {
                        // TODO: use actual peer_id from app identity
                        await channelService.send(channel: channel.name, fromId: "ios-app", content: text)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(newMessage.isEmpty)
            }
            .padding()
        }
        .navigationTitle("#\(channel.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await channelService.loadHistory(channel: channel.name)
        }
    }
}

struct MessageBubble: View {
    let message: ChannelMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.fromId.prefix(12).description)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                Spacer()

                Text(formatTime(message.sentAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(message.content)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatTime(_ iso: String) -> String {
        // Simple time extraction from ISO string
        if let tIndex = iso.firstIndex(of: "T"),
           let dotIndex = iso.firstIndex(of: ".") ?? iso.firstIndex(of: "+") {
            let timeStr = iso[iso.index(after: tIndex)..<dotIndex]
            return String(timeStr.prefix(5)) // HH:MM
        }
        return iso.suffix(8).description
    }
}
