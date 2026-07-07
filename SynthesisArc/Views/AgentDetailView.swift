import SwiftUI

/// Agent detail drill-down from Fleet View
struct AgentDetailView: View {
    let peer: Peer
    var usesInlineDM: Bool = false
    var onOpenInlineDM: (() -> Void)?
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var fleetService: FleetService
    @State private var showDirectorSheet = false
    @State private var showDM = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identitySection

                AgentQuickActionsPanel(
                    peer: peer,
                    onDM: {
                        if usesInlineDM, let onOpenInlineDM {
                            onOpenInlineDM()
                        } else {
                            showDM = true
                        }
                    },
                    onMention: {
                        FleetClipboard.copy("@\(peer.agentName)")
                        toastMessage = "Copied @\(peer.agentName)"
                    },
                    onCopyID: copyAgentID,
                    onDirector: { showDirectorSheet = true }
                )

                if let status = peer.blackboardStatus {
                    statusSection(status)
                }

                if let summary = peer.summary, !summary.isEmpty {
                    summarySection(summary)
                }
            }
            .padding()
        }
        .navigationTitle(peer.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showDirectorSheet) {
            QuickActionsSheet(peer: peer)
        }
        .sheet(isPresented: $showDM) {
            NavigationStack {
                DMView(peer: peer)
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            self.toastMessage = nil
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: toastMessage)
    }

    // MARK: - Sections

    private var identitySection: some View {
        HStack(spacing: 16) {
            AgentAvatarView(agentName: peer.agentName, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())

                Text(peer.agentName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                    if let bootState = peer.bootState {
                        Text(bootState)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    private func statusSection(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Blackboard Status", systemImage: "list.clipboard")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(status)
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Current Summary", systemImage: "text.alignleft")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.callout)
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        peer.name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var statusDotColor: Color {
        switch peer.statusColor {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    private func copyAgentID() {
        FleetClipboard.copy(peer.agentName)
        toastMessage = "Copied agent ID"
    }
}