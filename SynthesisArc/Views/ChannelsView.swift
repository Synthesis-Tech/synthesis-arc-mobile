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
    @EnvironmentObject var dmService: DMService
    @State private var newMessage = ""
    @State private var replyContext: ReplyContext?
    @State private var isLoadingHistory = false
    @State private var dmPresentation: DMPresentation?

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
                            parentMessage: parentMessage(for: msg),
                            onReply: { beginReply(to: msg) },
                            onDM: { agent, quoted in openDM(agentName: agent, quoting: quoted) },
                            onMention: { insertMention(agentName: $0) }
                        )
                    }
                }
            }

            Divider()

            VStack(spacing: 0) {
                if let reply = replyContext {
                    ReplyComposerBanner(context: reply) {
                        replyContext = nil
                    }
                    Divider()
                }

                GrowingMessageComposer(
                    text: $newMessage,
                    placeholder: "Message #\(channel.name)",
                    mentionCandidates: mentionCandidates,
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
        .sheet(item: $dmPresentation) { presentation in
            NavigationStack {
                DMView(peer: presentation.peer, replyContext: presentation.replyContext)
            }
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

    private func beginReply(to message: CoordMessage) {
        replyContext = ReplyContext.from(message: message, channel: channel.name)
    }

    private var mentionCandidates: [String] {
        var names = Set(fleetService.roster.allMemberNames)
        for peer in fleetService.peers {
            names.insert(peer.agentName)
        }
        names.remove(AppConfig.shared.agentName)
        return names.sorted()
    }

    private func refreshHistory() async {
        isLoadingHistory = true
        await channelService.loadHistory(channel: channel.name)
        isLoadingHistory = false
    }

    private func openDM(agentName: String, quoting message: CoordMessage) {
        dmPresentation = DMPresentation(
            peer: peer(for: agentName),
            replyContext: ReplyContext.from(message: message, channel: channel.name)
        )
    }

    private func insertMention(agentName: String) {
        newMessage = AgentMentionAutocomplete.insertMention(into: newMessage, agentName: agentName)
    }

    private func peer(for agentName: String) -> Peer {
        fleetService.peers.first(where: { $0.agentName == agentName })
            ?? Peer(
                agentName: agentName,
                pid: nil,
                cwd: nil,
                gitRoot: nil,
                summary: nil,
                status: .offline
            )
    }

    private func sendMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let replyId = replyContext?.messageId
        newMessage = ""
        replyContext = nil
        Task {
            await channelService.send(channel: channel.name, content: text, replyTo: replyId)
        }
    }
}

private struct DMPresentation: Identifiable {
    let peer: Peer
    let replyContext: ReplyContext?
    var id: String { peer.agentName }
}

struct MessageBubble: View {
    let message: CoordMessage
    var parentMessage: CoordMessage?
    var onReply: (() -> Void)?
    var onDM: ((String, CoordMessage) -> Void)?
    var onMention: ((String) -> Void)?
    @ObservedObject var nameResolver = PeerNameResolver.shared

    private var senderAgentName: String? {
        MessageAgentResolver.agentName(for: message)
    }

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
        .contextMenu {
            messageActions
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let agent = senderAgentName {
                Button {
                    onDM?(agent, message)
                } label: {
                    Label("DM", systemImage: "envelope.fill")
                }
                .tint(.indigo)

                Button {
                    onMention?(agent)
                } label: {
                    Label("Mention", systemImage: "at")
                }
                .tint(.blue)
            }
            Button {
                onReply?()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            .tint(.cyan)
        }
        #endif
    }

    @ViewBuilder
    private var messageActions: some View {
        if let agent = senderAgentName {
            Button {
                onDM?(agent, message)
            } label: {
                Label(
                    "DM \(AgentMentionAutocomplete.displayLabel(for: agent))",
                    systemImage: "envelope.fill"
                )
            }

            Button {
                onMention?(agent)
            } label: {
                Label("Mention @\(agent)", systemImage: "at")
            }
        }

        Button {
            onReply?()
        } label: {
            Label("Reply in thread", systemImage: "arrowshape.turn.up.left")
        }
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