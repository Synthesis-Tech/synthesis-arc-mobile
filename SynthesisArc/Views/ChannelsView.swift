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
                        description: Text("Channels appear when forge-graphd is reachable.")
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
            Image(systemName: channel.visibility == .private ? "lock.fill" : "number")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body.bold())
                if let description = channel.description, !description.isEmpty {
                    Text(description)
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

struct ChannelThreadView: View {
    let channel: Channel
    @EnvironmentObject var channelService: ChannelService
    @State private var newMessage = ""
    @State private var replyTo: CoordMessage?

    private var messages: [CoordMessage] {
        channelService.messages[channel.name] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if let err = channelService.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        Task { await channelService.loadHistory(channel: channel.name) }
                    } label: {
                        Text("Retry")
                            .font(.caption.bold())
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages, id: \.id) { msg in
                        MessageBubble(
                            message: msg,
                            parentMessage: parentMessage(for: msg)
                        )
                        .contextMenu {
                            Button {
                                replyTo = msg
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                        }
                        #if os(iOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                replyTo = msg
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                            .tint(.blue)
                        }
                        #endif
                    }
                }
                .padding()
            }

            Divider()

            VStack(spacing: 0) {
                if let reply = replyTo {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)

                        Text("Replying to \(replyTargetMention(for: reply))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            replyTo = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.08))

                    Divider()
                }

                HStack(spacing: 8) {
                    TextField("Message #\(channel.name)", text: $newMessage)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(newMessage.isEmpty)
                }
                .padding()
            }
        }
        .navigationTitle("#\(channel.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await channelService.loadHistory(channel: channel.name)
        }
    }

    private func parentMessage(for message: CoordMessage) -> CoordMessage? {
        guard let replyToId = message.replyTo else { return nil }
        return messages.first { $0.id == replyToId }
    }

    private func replyTargetMention(for message: CoordMessage) -> String {
        if let name = message.fromAgentName {
            return "@\(name)"
        }
        return "@\(PeerNameResolver.shared.resolve(message.from))"
    }

    private func sendMessage() {
        guard !newMessage.isEmpty else { return }
        let text = newMessage
        let replyId = replyTo?.id
        newMessage = ""
        replyTo = nil
        Task {
            await channelService.send(channel: channel.name, content: text, replyTo: replyId)
        }
    }
}

struct MessageBubble: View {
    let message: CoordMessage
    var parentMessage: CoordMessage?
    @ObservedObject var nameResolver = PeerNameResolver.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(senderName)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                Spacer()

                Text(message.sentAtDisplay)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let replyToId = message.replyTo {
                replyQuote(replyToId: replyToId)
            }

            MentionText(content: message.content)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func replyQuote(replyToId: NodeId) -> some View {
        if let parent = parentMessage {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(parentSenderName(parent))
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)

                    MentionText(content: parent.content, font: .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 2)
        } else {
            Text("↩ replying to message #\(replyToId)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var senderName: String {
        displayName(for: message)
    }

    private func parentSenderName(_ parent: CoordMessage) -> String {
        displayName(for: parent)
    }

    private func displayName(for message: CoordMessage) -> String {
        if let name = message.fromAgentName {
            return name.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return nameResolver.resolve(message.from)
    }
}