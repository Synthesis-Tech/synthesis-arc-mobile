import SwiftUI

/// Connection status bar — forge-graphd health + SSE live state
struct ConnectionStatusBar: View {
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService

    var body: some View {
        if !fleetService.graphdHealthy || fleetService.error != nil {
            errorBanner
        } else if streamService.isConnected {
            liveBanner
        } else if let streamError = streamService.lastError {
            reconnectingBanner(streamError)
        }
    }

    private var errorBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.exclamationmark")
                .font(.caption)
            Text(fleetService.error ?? "forge-graphd unreachable")
                .font(.caption)
            Spacer()
            Button("Retry") {
                Task {
                    await fleetService.bootAsPeer()
                    await fleetService.refresh()
                    streamService.start()
                }
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

    private var liveBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Live")
                .font(.caption.bold())
            Text("SSE coordination stream")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            GraphdHealthDot()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.green.opacity(0.08))
        .foregroundStyle(.primary)
    }

    private func reconnectingBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("Reconnecting SSE…")
                .font(.caption)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.1))
        .foregroundStyle(.orange)
    }
}

struct GraphdHealthDot: View {
    @EnvironmentObject var fleetService: FleetService

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(fleetService.graphdHealthy ? .green : .red)
                .frame(width: 6, height: 6)
            Text(fleetService.graphdHealthy ? "Graphd" : "Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}