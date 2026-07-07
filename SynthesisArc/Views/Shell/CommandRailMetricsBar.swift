import SwiftUI

/// 44pt command rail — fleet-wide metrics above the split columns (iPad landscape spec).
struct CommandRailMetricsBar: View {
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var channelService: ChannelService

    var body: some View {
        HStack(spacing: 16) {
            metric(
                value: fleetService.peers.count,
                label: "Online",
                color: .green,
                systemImage: "circle.grid.3x3"
            )
            metric(
                value: fleetService.peers.filter { $0.statusColor == .green }.count,
                label: "Active",
                color: .blue,
                systemImage: "bolt.fill"
            )
            metric(
                value: fleetService.exceptionCount,
                label: "Attention",
                color: .orange,
                systemImage: "exclamationmark.triangle.fill"
            )
            metric(
                value: dmService.unreadInboundCount,
                label: "Inbox",
                color: .red,
                systemImage: "tray.fill"
            )
            metric(
                value: channelService.totalChannelUnread,
                label: "Channels",
                color: .purple,
                systemImage: "number"
            )

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(streamService.isConnected ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(streamService.isConnected ? "Live" : "Polling")
                    .font(.caption.bold())
                GraphdHealthDot()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
    }

    private func metric(value: Int, label: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}