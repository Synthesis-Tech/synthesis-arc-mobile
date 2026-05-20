import SwiftUI

/// macOS menu bar extra — quick fleet health
#if os(macOS)
struct MenuBarView: View {
    @EnvironmentObject var fleetService: FleetService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fleet Status")
                .font(.headline)

            Divider()

            ForEach(fleetService.peers.prefix(10)) { peer in
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

            if fleetService.peers.isEmpty {
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
