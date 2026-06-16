import SwiftUI

/// DM view for bilateral agent communication
struct DMView: View {
    let peer: Peer
    @EnvironmentObject var dmService: DMService
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var sendError: String?

    private var client: ForgeGraphClient {
        AppConfig.shared.makeClient()
    }

    private var messages: [CoordMessage] {
        dmService.messages(with: peer.agentName)
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

            ScrollView {
                if isLoading && messages.isEmpty {
                    ProgressView("Loading messages...")
                        .padding(.top, 40)
                } else if messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "envelope",
                        description: Text("Start a conversation with \(displayName)")
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages, id: \.id) { msg in
                            DMBubble(
                                message: msg,
                                peerName: peer.agentName,
                                localAgentName: localAgentName
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message \(displayName)...", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .onSubmit {
                        guard !newMessage.isEmpty else { return }
                        let text = newMessage
                        newMessage = ""
                        Task { await sendDM(text) }
                    }

                Button {
                    guard !newMessage.isEmpty else { return }
                    let text = newMessage
                    newMessage = ""
                    Task { await sendDM(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(newMessage.isEmpty)
            }
            .padding()
        }
        .navigationTitle("DM: \(displayName)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadMessages()
        }
    }

    private var displayName: String {
        peer.agentName.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func loadMessages() async {
        isLoading = true
        do {
            let polled = try await client.pollMessages()
            dmService.seedInbound(polled)
        } catch {
            print("[DMView] loadMessages error: \(error)")
        }
        isLoading = false
    }

    private func sendDM(_ content: String) async {
        sendError = nil
        let optimistic = dmService.makeOptimisticOutbound(to: peer.agentName, content: content)
        dmService.appendOutbound(optimistic)
        do {
            try await client.sendDM(to: peer.agentName, content: content)
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