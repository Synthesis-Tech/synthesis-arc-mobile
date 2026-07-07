import SwiftUI

/// Left command rail — six destinations with live badge counts.
struct CommandRailSidebar: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var channelService: ChannelService

    var body: some View {
        List {
            ForEach(CommandDestination.allCases) { destination in
                Button {
                    commandCenterState.selectedDestination = destination
                } label: {
                    HStack {
                        Label(destination.title, systemImage: destination.systemImage)
                            .foregroundStyle(
                                commandCenterState.selectedDestination == destination
                                    ? Color.accentColor
                                    : Color.primary
                            )
                        Spacer(minLength: 8)
                        if let count = badgeCount(for: destination), count > 0 {
                            Text("\(count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badgeColor(for: destination))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(E2EAccessibility.nav(destination.rawValue))
                .listRowBackground(
                    commandCenterState.selectedDestination == destination
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
            }
        }
        .navigationTitle("Command")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func badgeCount(for destination: CommandDestination) -> Int? {
        switch destination {
        case .fleet:
            let count = fleetService.exceptionCount
            return count > 0 ? count : nil
        case .inbox:
            let count = dmService.unreadInboundCount
            return count > 0 ? count : nil
        case .channels:
            let count = channelService.totalChannelUnread
            return count > 0 ? count : nil
        case .director, .blackboard, .settings:
            return nil
        }
    }

    private func badgeColor(for destination: CommandDestination) -> Color {
        switch destination {
        case .fleet: return .orange
        case .inbox, .channels: return .red
        default: return .secondary
        }
    }
}