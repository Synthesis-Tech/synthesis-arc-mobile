import SwiftUI

/// Connection status bar — shows daemon reachability at the top of any view
struct ConnectionStatusBar: View {
    @EnvironmentObject var fleetService: FleetService

    var body: some View {
        if !fleetService.daemonHealthy {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption)
                Text(fleetService.error ?? "Daemon unreachable")
                    .font(.caption)
                Spacer()
                Button("Retry") {
                    Task { await fleetService.refresh() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red.opacity(0.15))
            .foregroundStyle(.red)
        }
    }
}

/// Inline daemon health indicator for headers
struct DaemonHealthDot: View {
    @EnvironmentObject var fleetService: FleetService

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(fleetService.daemonHealthy ? .green : .red)
                .frame(width: 6, height: 6)
            Text(fleetService.daemonHealthy ? "Connected" : "Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
