import SwiftUI

/// DM view for bilateral agent communication
struct DMView: View {
    let peer: Peer
    var replyContext: ReplyContext?
    var draftKeyOverride: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var composerDrafts: ComposerDraftStore
    @State private var isLoading = false
    @State private var sendError: String?
    @State private var didApplyReplyPrefix = false
    @State private var activeReplyContext: ReplyContext?

    private var client: ForgeGraphClient {
        AppConfig.shared.makeClient()
    }

    private var messages: [CoordMessage] {
        dmService.activeThreadMessages
    }

    private var localAgentName: String {
        AppConfig.shared.agentName
    }

    private var isPhoneLandscape: Bool {
        PhoneLandscapeLayout.isPhoneLandscape(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    private var draftKey: String {
        draftKeyOverride ?? ComposerDraftStore.inboxKey(peer.agentName)
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { composerDrafts.text(for: draftKey) },
            set: { composerDrafts.setText($0, for: draftKey) }
        )
    }

    var body: some View {
        PinnedComposerThreadLayout(isPhoneLandscape: isPhoneLandscape) {
            threadBody
        } composer: {
            composerBody
        }
        .navigationTitle("DM: \(displayName)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            UsabilityTrace.shared.trace("dm.thread.open", context: ["peer": peer.agentName])
            dmService.setActivePeer(peer.agentName)
            syncReplyContext(from: replyContext)
            Task {
                await dmService.markConversationDelivered(sender: peer.agentName)
            }
        }
        .onChange(of: replyContext) { _, newValue in
            syncReplyContext(from: newValue)
        }
        .onDisappear {
            dmService.setActivePeer(nil)
        }
        .task(id: peer.agentName) {
            await loadMessages()
            await dmService.hydrateThreadContent(for: peer.agentName)
        }
        .onDisappear {
            Task { await dmService.hydrateAllEmptyMessages() }
        }
        .task(id: replyContext?.messageId) {
            syncReplyContext(from: replyContext)
        }
    }

    @ViewBuilder
    private var threadBody: some View {
        VStack(spacing: 0) {
            if let err = sendError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                        .font(.caption)
                    Spacer()
                    Button { sendError = nil } label: {
                        Image(systemName: "xmark.circle")
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
            }

            Group {
                if isLoading && messages.isEmpty {
                    ScrollView {
                        ProgressView("Loading messages...")
                            .padding(.top, 40)
                    }
                } else if messages.isEmpty {
                    ScrollView {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "envelope",
                            description: Text("Start a conversation with \(displayName)")
                        )
                    }
                } else {
                    MessageThreadScrollView(messages: messages) { msg in
                        DMBubble(
                            message: msg,
                            peerName: peer.agentName,
                            localAgentName: localAgentName,
                            onReply: { beginReply(to: msg) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var composerBody: some View {
        VStack(spacing: 0) {
            if let activeReplyContext {
                ReplyComposerBanner(context: activeReplyContext) {
                    stripReplyPrefix()
                    self.activeReplyContext = nil
                }
                Divider()
            }

            GrowingMessageComposer(
                text: messageBinding,
                placeholder: "Message \(displayName)...",
                mentionCandidates: mentionCandidates,
                compactLineLimit: isPhoneLandscape,
                onSend: submitMessage
            )
            .padding(isPhoneLandscape ? 8 : 16)
        }
    }

    private var mentionCandidates: [String] {
        var names = Set(fleetService.roster.allMemberNames)
        for listed in fleetService.peers {
            names.insert(listed.agentName)
        }
        names.remove(AppConfig.shared.agentName)
        names.remove(peer.agentName)
        return names.sorted()
    }

    private var displayName: String {
        peer.agentName.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func loadMessages() async {
        isLoading = true
        await dmService.pollInbox()
        isLoading = false
    }

    private func syncReplyContext(from context: ReplyContext?) {
        let previousId = activeReplyContext?.messageId
        activeReplyContext = context
        guard let context else {
            didApplyReplyPrefix = false
            return
        }
        if previousId != context.messageId {
            didApplyReplyPrefix = false
            if messageBinding.wrappedValue.isEmpty
                || messageBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix("> replying to msg/") {
                composerDrafts.setText("", for: draftKey)
            }
        }
        guard !didApplyReplyPrefix, messageBinding.wrappedValue.isEmpty else { return }
        composerDrafts.setText(context.dmQuotePrefix, for: draftKey)
        didApplyReplyPrefix = true
    }

    private func stripReplyPrefix() {
        guard let activeReplyContext,
              messageBinding.wrappedValue.hasPrefix(activeReplyContext.dmQuotePrefix) else { return }
        composerDrafts.setText("", for: draftKey)
        didApplyReplyPrefix = false
    }

    private func beginReply(to message: CoordMessage) {
        activeReplyContext = ReplyContext.fromDM(message: message, peerAgentName: peer.agentName)
        didApplyReplyPrefix = false
        if messageBinding.wrappedValue.isEmpty {
            composerDrafts.setText(activeReplyContext?.dmQuotePrefix ?? "", for: draftKey)
            didApplyReplyPrefix = true
        }
    }

    private func submitMessage() {
        let text = messageBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let outbound = resolvedOutboundText(text)
        composerDrafts.setText("", for: draftKey)
        activeReplyContext = nil
        didApplyReplyPrefix = false
        Task { await sendDM(outbound) }
    }

    private func resolvedOutboundText(_ text: String) -> String {
        guard let reply = activeReplyContext else { return text }
        if text.contains(reply.referenceTag) {
            return text
        }
        return "\(reply.dmQuotePrefix)\(text)"
    }

    private func sendDM(_ content: String) async {
        sendError = nil
        let optimistic = dmService.makeOptimisticOutbound(to: peer.agentName, content: content)
        dmService.appendOutbound(optimistic)
        do {
            if let serverId = try await client.sendDM(to: peer.agentName, content: content) {
                dmService.confirmOutbound(
                    optimisticId: optimistic.id,
                    serverId: serverId,
                    to: peer.agentName,
                    content: content
                )
            }
            for delay in [2.0, 5.0, 10.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await dmService.pollInbox()
            }
        } catch {
            sendError = "Send failed: \(error.localizedDescription)"
        }
    }
}

struct DMBubble: View {
    let message: CoordMessage
    let peerName: String
    let localAgentName: String
    var onReply: (() -> Void)?
    @ObservedObject var nameResolver = PeerNameResolver.shared
    @State private var isHovered = false

    private var isFromPeer: Bool {
        message.isFromPeer(peerAgentName: peerName, localAgent: localAgentName)
    }

    private var rosterAgents: [String] {
        var names = Set(nameResolver.nameMap.keys)
        names.insert(peerName)
        names.insert(localAgentName)
        return names.sorted()
    }

    private var senderSlug: String {
        if isFromPeer {
            return nameResolver.resolvedAgentSlug(for: message, rosterAgents: rosterAgents) ?? peerName
        }
        return localAgentName
    }

    private var senderLabel: String {
        if isFromPeer {
            return nameResolver.displaySenderLabel(for: message, rosterAgents: rosterAgents)
        }
        return AgentMentionAutocomplete.displayLabel(for: localAgentName)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isFromPeer { Spacer(minLength: 24) }

            if isFromPeer {
                AgentAvatarView(agentName: senderSlug, size: 28)
            }

            VStack(alignment: isFromPeer ? .leading : .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Text(senderLabel)
                        .font(.caption.bold())
                    Text(message.sentAtFullDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isHovered {
                        if let onReply {
                            Button(action: onReply) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            FleetClipboard.copy(message.content)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let channel = message.embeddedChannelReference {
                    Label("#\(channel)", systemImage: "number")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if message.hasReadableBody {
                    Text(message.readableBody)
                        .font(.callout)
                        .textSelection(.enabled)
                        .multilineTextAlignment(isFromPeer ? .leading : .trailing)
                } else if message.hasDisplayableContent {
                    Text(message.content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .multilineTextAlignment(isFromPeer ? .leading : .trailing)
                } else {
                    Text("Loading message…")
                        .font(.callout.italic())
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(isFromPeer ? .leading : .trailing)
                }
            }
            .padding(10)
            .background(isFromPeer ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
            #if os(iOS)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered.toggle()
                }
            }
            #endif
            .contextMenu {
                if let onReply {
                    Button(action: onReply) {
                        Label("Reply in thread", systemImage: "arrowshape.turn.up.left")
                    }
                }
                Button {
                    FleetClipboard.copy("msg/\(message.id)")
                } label: {
                    Label("Copy msg/\(message.id)", systemImage: "number")
                }
            }

            if isFromPeer { Spacer(minLength: 24) }
        }
    }

}