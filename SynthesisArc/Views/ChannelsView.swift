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
    @EnvironmentObject var fleetService: FleetService
    @State private var newMessage = ""
    @State private var replyTo: CoordMessage?
    @State private var isLoadingHistory = false

    private var messages: [CoordMessage] {
        channelService.activeMessages
    }

    var body: some View {
        VStack(spacing: 0) {
            if let err = channelService.threadError {
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

            Group {
                if isLoadingHistory && messages.isEmpty {
                    ScrollView {
                        ProgressView("Loading history...")
                            .padding(.top, 40)
                    }
                } else if messages.isEmpty {
                    ScrollView {
                        ContentUnavailableView(
                            "No Messages Yet",
                            systemImage: "bubble.left",
                            description: Text("Past messages load from forge-graphd when you open a channel.")
                        )
                        .padding(.top, 24)
                    }
                } else {
                    MessageThreadScrollView(messages: messages) { msg in
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

                GrowingMessageComposer(
                    text: $newMessage,
                    placeholder: "Message #\(channel.name)",
                    onSend: sendMessage
                )
                .padding()
            }
        }
        .navigationTitle("#\(channel.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await refreshHistory() }
                } label: {
                    if isLoadingHistory {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoadingHistory)
                .accessibilityLabel("Refresh channel")
            }
        }
        .refreshable {
            await refreshHistory()
        }
        .onAppear {
            channelService.setActiveChannel(channel.name)
        }
        .onDisappear {
            channelService.setActiveChannel(nil)
        }
        .task(id: channel.name) {
            isLoadingHistory = true
            if !fleetService.isBooted {
                for _ in 0..<30 where !fleetService.isBooted {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            await channelService.loadHistory(channel: channel.name)
            isLoadingHistory = false
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

    private func refreshHistory() async {
        isLoadingHistory = true
        await channelService.loadHistory(channel: channel.name)
        isLoadingHistory = false
    }

    private func sendMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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