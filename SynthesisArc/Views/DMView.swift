import SwiftUI

/// DM view for bilateral agent communication
struct DMView: View {
    let peer: Peer
    var replyContext: ReplyContext?
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var fleetService: FleetService
    @State private var newMessage = ""
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

    var body: some View {
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
                            localAgentName: localAgentName
                        )
                    }
                }
            }

            if let activeReplyContext {
                ReplyComposerBanner(context: activeReplyContext) {
                    stripReplyPrefix()
                    self.activeReplyContext = nil
                }
                Divider()
            }

            GrowingMessageComposer(
                text: $newMessage,
                placeholder: "Message \(displayName)...",
                mentionCandidates: mentionCandidates,
                onSend: submitMessage
            )
            .padding()
        }
        .navigationTitle("DM: \(displayName)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            dmService.setActivePeer(peer.agentName)
            activeReplyContext = replyContext
            applyReplyPrefixIfNeeded()
        }
        .onDisappear {
            dmService.setActivePeer(nil)
        }
        .task(id: peer.agentName) {
            await loadMessages()
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

    private func applyReplyPrefixIfNeeded() {
        guard !didApplyReplyPrefix, let activeReplyContext, newMessage.isEmpty else { return }
        newMessage = activeReplyContext.dmQuotePrefix
        didApplyReplyPrefix = true
    }

    private func stripReplyPrefix() {
        guard let activeReplyContext, newMessage.hasPrefix(activeReplyContext.dmQuotePrefix) else { return }
        newMessage = ""
        didApplyReplyPrefix = false
    }

    private func submitMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newMessage = ""
        Task { await sendDM(text) }
    }

    private func sendDM(_ content: String) async {
        sendError = nil
        let optimistic = dmService.makeOptimisticOutbound(to: peer.agentName, content: content)
        dmService.appendOutbound(optimistic)
        do {
            try await client.sendDM(to: peer.agentName, content: content)
            // Agents reply asynchronously — poll a few times for the response.
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

    private var isFromPeer: Bool {
        message.isFromPeer(peerAgentName: peerName, localAgent: localAgentName)
    }

    var body: some View {
        HStack {
            if !isFromPeer { Spacer(minLength: 40) }

            VStack(alignment: isFromPeer ? .leading : .trailing, spacing: 4) {
                Text(message.content)
                    .font(.callout)
                    .textSelection(.enabled)

                Text(message.sentAtDisplay)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(isFromPeer ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isFromPeer { Spacer(minLength: 40) }
        }
    }
}