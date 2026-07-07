import SwiftUI

/// Channels tab — list of channels with message threads
struct ChannelsView: View {
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var commandCenterState: CommandCenterState
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var showCreateChannel = false
    @State private var channelToOpenAfterCreate: String?
    
    private var filteredChannels: [Channel] {
        if searchText.isEmpty {
            return channelService.channels
        }
        return channelService.channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(searchText) ||
            (channel.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Manual search field to avoid iOS 27 beta bug with .searchable()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search channels", text: $searchText)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(searchFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                Divider()
                
                Group {
                    if channelService.channels.isEmpty && !channelService.isLoading {
                        ContentUnavailableView(
                            "No Channels",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Channels appear when forge-graphd is reachable.")
                        )
                    } else if filteredChannels.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search
                    } else {
                        List(filteredChannels) { channel in
                            NavigationLink(value: channel.name) {
                                ChannelRow(channel: channel)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Channels")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateChannel = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create channel")
                }
            }
            .sheet(isPresented: $showCreateChannel, onDismiss: openChannelAfterCreateIfNeeded) {
                CreateChannelSheet { name in
                    channelToOpenAfterCreate = name
                }
            }
            .task {
                await channelService.loadChannels()
            }
            .refreshable {
                await channelService.loadChannels()
            }
            .navigationDestination(for: String.self) { channelName in
                if let channel = channelService.resolvedChannel(named: channelName) {
                    ChannelThreadView(channel: channel)
                        .id(channelName)
                }
            }
            .onChange(of: commandCenterState.deepLinkEpoch) { _, _ in
                openDeepLinkedChannelIfNeeded()
            }
        }
    }

    private func openChannelAfterCreateIfNeeded() {
        guard let name = channelToOpenAfterCreate else { return }
        channelToOpenAfterCreate = nil
        commandCenterState.selectChannel(name)
        navigationPath.append(name)
    }

    private func openDeepLinkedChannelIfNeeded() {
        guard commandCenterState.phoneTab == .channels,
              let name = commandCenterState.selectedChannelName else { return }
        navigationPath = NavigationPath([name])
    }

    private var searchFieldBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.systemGray6)
        #endif
    }
}

struct ChannelRow: View {
    let channel: Channel
    @EnvironmentObject var channelService: ChannelService

    private var unread: Int {
        channelService.channelUnread[channel.name] ?? 0
    }

    private var preview: ChannelPreview? {
        channelService.channelPreviews[channel.name]
    }

    private var isUnread: Bool { unread > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: channel.visibility == .private ? "lock.fill" : "number")
                .font(.body.weight(.medium))
                .foregroundStyle(isUnread ? .primary : .secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("#\(channel.name)")
                        .font(isUnread ? .subheadline.bold() : .subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    } else if let preview, !preview.relativeTime.isEmpty {
                        Text(preview.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(previewText)
                    .font(.callout)
                    .fontWeight(isUnread ? .medium : .regular)
                    .lineLimit(2)
                    .foregroundStyle(previewForeground)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    private var previewForeground: Color {
        if previewText == "No messages yet" || previewText == "Tap to view message" {
            return Color.secondary.opacity(0.75)
        }
        return isUnread ? .primary : .secondary
    }

    private var previewText: String {
        if let preview {
            if !preview.previewLine.isEmpty {
                return preview.previewLine
            }
            if preview.lastTimestamp > 0 {
                return "Tap to view message"
            }
        }
        if let description = channel.description, !description.isEmpty {
            return description
        }
        return "No messages yet"
    }
}

struct ChannelThreadView: View {
    let channel: Channel
    var onOpenInlineDM: ((Peer, ReplyContext?) -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var composerDrafts: ComposerDraftStore
    @State private var replyContext: ReplyContext?
    @State private var isLoadingHistory = false
    @State private var isJoiningChannel = false
    @State private var dmPresentation: DMPresentation?
    @State private var showInviteSheet = false
    @State private var sendError: String?

    private var showsJoinGate: Bool {
        channelService.requiresJoinGate(for: channel)
    }

    private var messages: [CoordMessage] {
        channelService.threadMessages(for: channel.name)
    }

    private var channelThreadError: String? {
        channelService.threadError(for: channel.name)
    }

    private var isPhoneLandscape: Bool {
        PhoneLandscapeLayout.isPhoneLandscape(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    private var draftKey: String {
        ComposerDraftStore.channelKey(channel.name)
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { composerDrafts.text(for: draftKey) },
            set: { composerDrafts.setText($0, for: draftKey) }
        )
    }

    var body: some View {
        PinnedComposerThreadLayout(isPhoneLandscape: isPhoneLandscape) {
            threadContent
        } composer: {
            composerSection
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(E2EAccessibility.channelComposer)
        }
        .navigationTitle("#\(channel.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showInviteSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Invite to channel")
            }
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
        .sheet(isPresented: $showInviteSheet) {
            ChannelInviteSheet(channel: channel)
        }
        .refreshable {
            await refreshHistory()
        }
        .sheet(item: $dmPresentation) { presentation in
            NavigationStack {
                DMView(peer: presentation.peer, replyContext: presentation.replyContext)
            }
        }
        .task(id: channel.name) {
            channelService.setActiveChannel(channel.name)
            guard !Task.isCancelled else { return }
            guard !showsJoinGate else { return }
            let span = UsabilityTrace.shared.beginSpan(
                "channel.open",
                context: ["channel": channel.name]
            )
            let hasCachedMessages = !channelService.threadMessages(for: channel.name).isEmpty
            if !hasCachedMessages {
                isLoadingHistory = true
            }
            defer {
                isLoadingHistory = false
                UsabilityTrace.shared.endSpan(
                    span,
                    outcome: messages.isEmpty && channelThreadError == nil ? "empty" : "ok",
                    extra: ["message_count": String(messages.count)]
                )
            }
            guard !Task.isCancelled else { return }
            _ = await channelService.openChannelThread(channel.name)
        }
        .onChange(of: channelThreadError) { _, error in
            if error != nil {
                isLoadingHistory = false
            }
        }
    }

    @ViewBuilder
    private var threadContent: some View {
        VStack(spacing: 0) {
            if showsJoinGate {
                privateChannelJoinGate
            } else if let err = channelThreadError {
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
                if isLoadingHistory && messages.isEmpty && channelThreadError == nil {
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

            ChannelHeaderBar(channel: channel)
        }
    }

    private var privateChannelJoinGate: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text("Private Channel")
                    .font(.title3.bold())

                Text("#\(channel.name) is private. Join to read and post in this channel.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if PrincipalContext.shared.isConfigured {
                    Text("As principal, you can join to read and post.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await joinPrivateChannel() }
                } label: {
                    if isJoiningChannel {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Label("Join #\(channel.name)", systemImage: "person.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isJoiningChannel)
                .accessibilityIdentifier(E2EAccessibility.channelJoin)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var composerSection: some View {
        if showsJoinGate {
            EmptyView()
        } else {
        VStack(spacing: 0) {
            Divider()

            if let err = sendError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button { sendError = nil } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.14))
                .foregroundStyle(.orange)
            }

            if let reply = replyContext {
                VStack(spacing: 0) {
                    ReplyComposerBanner(context: reply, showChannelTag: false) {
                        replyContext = nil
                        sendError = nil
                    }

                    Divider().opacity(0.25)

                    GrowingMessageComposer(
                        text: messageBinding,
                        placeholder: composerPlaceholder,
                        mentionCandidates: mentionCandidates,
                        isReplyMode: true,
                        compactLineLimit: isPhoneLandscape,
                        onSend: sendMessage
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.blue.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                GrowingMessageComposer(
                    text: messageBinding,
                    placeholder: composerPlaceholder,
                    mentionCandidates: mentionCandidates,
                    isReplyMode: false,
                    compactLineLimit: isPhoneLandscape,
                    onSend: sendMessage
                )
                .padding(.horizontal, 12)
                .padding(.vertical, isPhoneLandscape ? 6 : 12)
            }
        }
        }
    }

    private func joinPrivateChannel() async {
        isJoiningChannel = true
        defer { isJoiningChannel = false }
        _ = await channelService.joinAndOpenThread(channel.name)
    }

    private func parentMessage(for message: CoordMessage) -> CoordMessage? {
        guard let replyToId = message.replyTo else { return nil }
        return messages.first { $0.id == replyToId }
    }

    private func beginReply(to message: CoordMessage) {
        replyContext = ReplyContext.from(
            message: message,
            channel: channel.name,
            rosterAgents: mentionCandidates
        )
    }

    private var composerPlaceholder: String {
        if let reply = replyContext, reply.prefersDirectMessage {
            return "Message \(reply.compactSenderLabel)…"
        }
        if replyContext != nil {
            return "Reply in #\(channel.name)…"
        }
        return "Message #\(channel.name)"
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
        defer { isLoadingHistory = false }
        await channelService.loadHistory(channel: channel.name, force: true)
    }

    private func openDM(agentName: String, quoting message: CoordMessage) {
        let context = ReplyContext.from(
            message: message,
            channel: channel.name,
            rosterAgents: mentionCandidates
        )
        let targetPeer = peer(for: agentName)
        if let onOpenInlineDM {
            onOpenInlineDM(targetPeer, context)
        } else {
            dmPresentation = DMPresentation(peer: targetPeer, replyContext: context)
        }
    }

    private func insertMention(agentName: String) {
        let updated = AgentMentionAutocomplete.insertMention(
            into: messageBinding.wrappedValue,
            agentName: agentName
        )
        composerDrafts.setText(updated, for: draftKey)
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
        let text = messageBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let activeReply = replyContext
        composerDrafts.setText("", for: draftKey)
        replyContext = nil
        sendError = nil

        if let activeReply {
            let resolved = resolveReplyContext(activeReply)
            let parent = messages.first(where: { $0.id == activeReply.messageId })
            let enrichedParent = parent.map { PeerNameResolver.shared.enrich($0) }
            let localAgent = AppConfig.shared.agentName

            if let enrichedParent,
               let targetAgent = MessageAgentResolver.replyDMTarget(
                   for: enrichedParent,
                   rosterAgents: mentionCandidates
               ),
               targetAgent != localAgent {
                var outbound = text
                if !text.contains(resolved.referenceTag) {
                    outbound = "\(resolved.dmQuotePrefix)\(text)"
                }
                Task { await sendTargetedReply(to: targetAgent, content: outbound) }
                return
            }

            var outbound = text
            if !text.contains(resolved.referenceTag) {
                outbound = "\(resolved.channelReplyHeader)\n\(text)"
            }
            Task {
                await channelService.send(
                    channel: channel.name,
                    content: outbound,
                    replyTo: resolved.messageId
                )
            }
            return
        }

        Task {
            await channelService.send(channel: channel.name, content: text)
        }
    }

    private func resolveReplyContext(_ context: ReplyContext) -> ReplyContext {
        if context.senderAgentName != nil { return context }
        guard let parent = messages.first(where: { $0.id == context.messageId }) else { return context }
        return ReplyContext.from(
            message: parent,
            channel: context.channelName,
            rosterAgents: mentionCandidates
        )
    }

    /// Bilateral reply — DM tier (push) so only the parent-message author is notified.
    private func sendTargetedReply(to agentName: String, content: String) async {
        let client = AppConfig.shared.makeClient()
        let optimistic = dmService.makeOptimisticOutbound(to: agentName, content: content)
        dmService.appendOutbound(optimistic)
        do {
            if let serverId = try await client.sendDM(to: agentName, content: content) {
                dmService.confirmOutbound(
                    optimisticId: optimistic.id,
                    serverId: serverId,
                    to: agentName,
                    content: content
                )
            }
        } catch {
            sendError = "DM to @\(agentName) failed: \(error.localizedDescription)"
        }
    }
}

private struct DMPresentation: Identifiable {
    let peer: Peer
    let replyContext: ReplyContext?
    var id: String {
        if let replyContext {
            return "\(peer.agentName)-\(replyContext.messageId)"
        }
        return peer.agentName
    }
}

struct MessageBubble: View {
    let message: CoordMessage
    var parentMessage: CoordMessage?
    var onReply: (() -> Void)?
    var onDM: ((String, CoordMessage) -> Void)?
    var onMention: ((String) -> Void)?
    @EnvironmentObject var fleetService: FleetService
    @ObservedObject var nameResolver = PeerNameResolver.shared
    @State private var isHovered = false
    @State private var showActionsPinned = false

    private var showMessageActions: Bool {
        #if os(iOS)
        return showActionsPinned
        #else
        return isHovered || showActionsPinned
        #endif
    }

    private var actionsEmphasized: Bool {
        #if os(iOS)
        return showActionsPinned
        #else
        return isHovered || showActionsPinned
        #endif
    }

    private var rosterAgents: [String] {
        var names = Set(fleetService.roster.allMemberNames)
        for peer in fleetService.peers { names.insert(peer.agentName) }
        names.formUnion(nameResolver.nameMap.keys)
        names.remove(AppConfig.shared.agentName)
        return names.sorted()
    }

    private var senderAgentName: String? {
        nameResolver.resolvedAgentSlug(for: message, rosterAgents: rosterAgents)
    }

    private var agentSlug: String {
        senderAgentName ?? "unknown"
    }

    private var senderLabel: String {
        nameResolver.displaySenderLabel(for: message, rosterAgents: rosterAgents)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentAvatarView(agentName: agentSlug, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(senderLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Text("msg/\(message.id)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.quaternary)

                    Text(message.sentAtFullDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 4)

                    if showMessageActions {
                        inlineActionBar(emphasized: actionsEmphasized)
                    }
                }

                if !showMessageActions {
                    inlineActionBar(emphasized: false)
                        .opacity(0.5)
                }

                if let replyToId = message.replyTo {
                    replyQuote(replyToId: replyToId)
                }

                MentionText(content: message.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                showActionsPinned.toggle()
            }
        }
        .contextMenu {
            messageActions
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { onReply?() } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            .tint(.cyan)

            if let agent = senderAgentName {
                Button { onMention?(agent) } label: {
                    Label("Mention", systemImage: "at")
                }
                .tint(.blue)

                Button { onDM?(agent, message) } label: {
                    Label("DM", systemImage: "envelope.fill")
                }
                .tint(.indigo)
            }
        }
        #endif
    }

    @ViewBuilder
    private func inlineActionBar(emphasized: Bool) -> some View {
        MessageActionBar(
            onReply: onReply,
            onDM: senderAgentName.map { agent in
                { onDM?(agent, message) }
            },
            onMention: senderAgentName.map { agent in
                { onMention?(agent) }
            },
            onCopyRef: {
                FleetClipboard.copy("msg/\(message.id)")
            },
            emphasized: emphasized
        )
    }

    @ViewBuilder
    private var messageActions: some View {
        Button { onReply?() } label: {
            if let agent = senderAgentName {
                Label("Reply to @\(agent)", systemImage: "arrowshape.turn.up.left")
            } else {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }

        if let agent = senderAgentName {
            Button { onMention?(agent) } label: {
                Label("Mention @\(agent)", systemImage: "at")
            }

            Button { onDM?(agent, message) } label: {
                Label("DM quoting this message", systemImage: "envelope.fill")
            }
        }

        Button {
            FleetClipboard.copy("msg/\(message.id)")
        } label: {
            Label("Copy msg/\(message.id)", systemImage: "number")
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

    private func parentSenderName(_ parent: CoordMessage) -> String {
        nameResolver.displaySenderLabel(for: parent, rosterAgents: rosterAgents)
    }
}
