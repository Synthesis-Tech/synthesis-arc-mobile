import SwiftUI

/// Inbox view — shows DMs sent to daniel-willitzer
struct InboxView: View {
    @EnvironmentObject var fleetService: FleetService
    @State private var messages: [PeerDM] = []
    @State private var isLoading = false
    @State private var error: String?
    @ObservedObject var nameResolver = PeerNameResolver.shared

    private let daemon = DaemonClient()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && messages.isEmpty {
                    ProgressView("Loading inbox...")
                        .padding(.top, 40)
                } else if let error, messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadInbox() } }
                    }
                    .padding(.top, 40)
                } else if messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "tray",
                        description: Text("DMs from the fleet will appear here")
                    )
                } else {
                    List(messages, id: \.id) { msg in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(nameResolver.resolve(msg.fromId))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text(formatTime(msg.sentAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(msg.content)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await loadInbox() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadInbox()
            }
            .refreshable {
                await loadInbox()
            }
        }
    }

    private func loadInbox() async {
        isLoading = true
        error = nil
        do {
            // Poll DMs using the registered peer_id, or fallback to name-based
            if let peerId = fleetService.myPeerId {
                messages = try await daemon.pollMessages(peerId: peerId, markDelivered: false)
            } else {
                // Try name-based poll
                messages = try await daemon.pollMessagesByName(name: "daniel-willitzer", markDelivered: false)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func formatTime(_ iso: String) -> String {
        if let tIndex = iso.firstIndex(of: "T"),
           let dotIndex = iso.firstIndex(of: ".") ?? iso.firstIndex(of: "+") {
            return String(iso[iso.index(after: tIndex)..<dotIndex].prefix(5))
        }
        return iso.suffix(8).description
    }
}
