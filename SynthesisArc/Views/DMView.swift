import SwiftUI

/// DM (Direct Message) view for bilateral agent communication
struct DMView: View {
    let peer: Peer
    @State private var messages: [PeerDM] = []
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var error: String?

    private let daemon = DaemonClient()

    var body: some View {
        VStack(spacing: 0) {
            // Messages
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
                            DMBubble(message: msg, peerName: peer.name)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Compose bar
            HStack(spacing: 8) {
                TextField("Message \(displayName)...", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif

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
        peer.name.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func loadMessages() async {
        isLoading = true
        do {
            // Poll messages addressed to this peer (peek without marking delivered)
            messages = try await daemon.pollMessages(peerId: peer.id, markDelivered: false)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func sendDM(_ content: String) async {
        do {
            try await daemon.sendDM(fromId: "ios-app", toName: peer.name, content: content)
            // Reload to show sent message
            await loadMessages()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DMBubble: View {
    let message: PeerDM
    let peerName: String

    private var isFromPeer: Bool {
        // If the from_id contains the peer name pattern, it's from the peer
        message.fromId.contains(peerName) || message.fromId.starts(with: "name:")
    }

    var body: some View {
        HStack {
            if !isFromPeer { Spacer(minLength: 40) }

            VStack(alignment: isFromPeer ? .leading : .trailing, spacing: 4) {
                Text(message.content)
                    .font(.callout)
                    .textSelection(.enabled)

                Text(formatTime(message.sentAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(isFromPeer ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isFromPeer { Spacer(minLength: 40) }
        }
    }

    private func formatTime(_ iso: String) -> String {
        if let tIndex = iso.firstIndex(of: "T"),
           let dotIndex = iso.firstIndex(of: ".") ?? iso.firstIndex(of: "+") {
            return String(iso[iso.index(after: tIndex)..<dotIndex].prefix(5))
        }
        return iso.suffix(8).description
    }
}
