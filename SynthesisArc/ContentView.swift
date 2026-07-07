import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var dmService: DMService
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var streamService: CoordinationStreamService
    @ObservedObject private var deepLinkCoordinator = DeepLinkCoordinator.shared

    var body: some View {
        Group {
            #if os(iOS)
            if E2EMode.isActive || horizontalSizeClass == .regular {
                CommandCenterShellView()
            } else {
                PhoneTabShell()
            }
            #else
            CommandCenterShellView()
            #endif
        }
        .onChange(of: deepLinkCoordinator.publishEpoch) { _, _ in
            consumePendingDeepLink()
        }
        .task {
            consumePendingDeepLink()
        }
    }

    private func consumePendingDeepLink() {
        guard let route = deepLinkCoordinator.consume() else { return }
        CoordinationAuditLog.shared.log("Deep link consumed → \(route.auditLabel)", category: .lifecycle)
        commandCenterState.apply(route: route)
        switch route {
        case .inbox(let sender):
            Task {
                await dmService.markConversationDelivered(sender: sender)
                await dmService.hydrateThreadContent(for: sender)
                streamService.reduceUnread(by: dmService.messages(from: sender).count)
            }
        case .channel(let name):
            channelService.setActiveChannel(name)
            Task {
                _ = await channelService.openChannelThread(name)
            }
        case .fleet:
            break
        }
    }
}