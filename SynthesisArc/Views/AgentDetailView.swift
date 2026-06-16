import SwiftUI

/// Agent detail drill-down from Fleet View
struct AgentDetailView: View {
    let peer: Peer
    @EnvironmentObject var channelService: ChannelService
    @State private var showDirectorSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Identity header
                identitySection

                // Blackboard status
                if let status = peer.blackboardStatus {
                    statusSection(status)
                }

                // Summary
                if let summary = peer.summary, !summary.isEmpty {
                    summarySection(summary)
                }

                // Quick actions
                actionsSection
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
    }

    // MARK: - Sections

    private var identitySection: some View {
        HStack(spacing: 16) {
            // Agent avatar placeholder
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                Text(initials)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())

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

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Actions", systemImage: "bolt.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                NavigationLink(destination: DMView(peer: peer)) {
                    VStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.title3)
                        Text("DM")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    showDirectorSheet = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.title3)
                        Text("Director")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        peer.name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var initials: String {
        let parts = peer.name.split(separator: "-")
        return parts.prefix(2).map { String($0.prefix(1).uppercased()) }.joined()
    }

    private var statusDotColor: Color {
        switch peer.statusColor {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }
}
