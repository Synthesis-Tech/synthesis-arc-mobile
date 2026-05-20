import SwiftUI

/// Fleet View — home tab showing all active agents in a grid
struct FleetView: View {
    @EnvironmentObject var fleetService: FleetService

    let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if fleetService.isLoading && fleetService.peers.isEmpty {
                    ProgressView("Loading fleet...")
                        .padding(.top, 60)
                } else if let error = fleetService.error, fleetService.peers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await fleetService.refresh() }
                        }
                    }
                    .padding(.top, 60)
                } else {
                    fleetHeader
                    agentGrid
                }
            }
            .navigationTitle("Fleet")
            .refreshable {
                await fleetService.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await fleetService.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Fleet Header

    private var fleetHeader: some View {
        HStack(spacing: 20) {
            statBadge(
                count: fleetService.peers.count,
                label: "Online",
                color: .green
            )
            statBadge(
                count: fleetService.peers.filter { $0.statusColor == .green }.count,
                label: "Active",
                color: .blue
            )
            statBadge(
                count: fleetService.peers.filter { $0.statusColor == .yellow }.count,
                label: "Idle",
                color: .orange
            )
        }
        .padding()
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }

    // MARK: - Agent Grid

    private var agentGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(fleetService.peers) { peer in
                NavigationLink(destination: AgentDetailView(peer: peer)) {
                    AgentCard(peer: peer)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    let peer: Peer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusDot
                Text(displayName)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }

            if let bootState = peer.bootState {
                Text(bootState)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(bootStateColor(bootState))
            }

            if let summary = peer.blackboardStatus ?? (peer.summary.isEmpty ? nil : peer.summary) {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(statusBorderColor, lineWidth: 1)
        )
    }

    private var displayName: String {
        peer.name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)
    }

    private var statusDotColor: Color {
        switch peer.statusColor {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    private var statusBorderColor: Color {
        statusDotColor.opacity(0.3)
    }

    private func bootStateColor(_ state: String) -> Color {
        switch state {
        case "woke_up": return .green
        case "reconstructed": return .orange
        case "performed": return .yellow
        case "degraded": return .red
        default: return .secondary
        }
    }
}
