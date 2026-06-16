import SwiftUI

/// macOS menu bar extra — quick fleet health
#if os(macOS)
struct MenuBarView: View {
    @EnvironmentObject var fleetService: FleetService
    @AppStorage(FleetWatchlist.storageKey) private var watchlistRaw = ""

    private var watchlist: Set<String> {
        FleetWatchlist.decode(watchlistRaw)
    }

    private var menuBarPeers: [Peer] {
        let pinned = fleetService.peers.filter { watchlist.contains($0.agentName) }
        let attention = fleetService.peersNeedingAttention(watchlist: watchlist)
        var seen = Set<String>()
        var result: [Peer] = []
        for peer in pinned + attention {
            if seen.insert(peer.agentName).inserted {
                result.append(peer)
            }
            if result.count >= 10 { break }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fleet Status")
                .font(.headline)

            if fleetService.exceptionCount > 0 {
                Text("\(fleetService.exceptionCount) need attention")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            ForEach(menuBarPeers) { peer in
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor(peer))
                        .frame(width: 6, height: 6)
                    Text(peer.name)
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    if let boot = peer.bootState {
                        Text(boot)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if menuBarPeers.isEmpty {
                Text("No agents online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Refresh") {
                Task { await fleetService.refresh() }
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 260)
    }

    private func dotColor(_ peer: Peer) -> Color {
        switch peer.statusColor {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }
}
#endif
