import SwiftUI

/// Connection status bar — graphd health first; SSE is optional acceleration.
struct ConnectionStatusBar: View {
    @ObservedObject private var hotLayer = CoordinationHotLayer.shared
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var channelService: ChannelService

    var body: some View {
        if fleetService.isBootstrapping {
            reconnectingBanner(
                title: "Reconnecting…",
                subtitle: fleetService.graphdHealthy ? "Re-booting peer session" : "Connecting to forge-graphd"
            )
        } else if !fleetService.graphdHealthy || fleetService.error != nil {
            errorBanner
        } else if streamService.isConnected {
            sseLiveBanner
        } else if streamService.isPendingConnection || streamService.isConnecting {
            reconnectingBanner(
                title: "Connecting live stream…",
                subtitle: "REST polling active"
            )
        } else if fleetService.isBooted {
            restLiveBanner
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
                    fleetService.isBootstrapping = true
                    defer { fleetService.isBootstrapping = false }
                    await fleetService.bootAsPeer(reason: "status-bar-retry")
                    CoordinationHotLayer.shared.start(
                        fleetService: fleetService,
                        dmService: dmService,
                        channelService: channelService,
                        streamService: streamService
                    )
                    streamService.start(force: true)
                    await fleetService.completeBootSetup()
                }
            }
            .disabled(fleetService.isBootstrapping)
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.15))
        .foregroundStyle(.red)
    }

    private var sseLiveBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Live")
                .font(.caption.bold())
            Text("SSE + REST")
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

    private var restLiveBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Live")
                .font(.caption.bold())
            Text(restSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            GraphdHealthDot()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.green.opacity(0.08))
        .foregroundStyle(.primary)
    }

    private func reconnectingBanner(title: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GraphdHealthDot()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.12))
        .foregroundStyle(.orange)
    }

    private var restSubtitle: String {
        if hotLayer.isRunning {
            if streamService.isPendingConnection || streamService.isConnecting {
                return "REST poll · SSE connecting"
            }
            return "REST poll · SSE optional"
        }
        return "REST coordination"
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