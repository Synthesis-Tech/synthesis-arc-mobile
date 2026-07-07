import Foundation
import Combine

/// Phone tab indices — aligned with PhoneTabShell TabView order.
enum PhoneTab: Int, Hashable, CaseIterable {
    case fleet = 0
    case inbox = 1
    case channels = 2
    case director = 3
    case blackboard = 4
    case settings = 5
}

/// Primary navigation destinations in the iPad command center (mirrors phone tabs).
enum CommandDestination: String, CaseIterable, Identifiable, Hashable {
    case fleet
    case inbox
    case channels
    case director
    case blackboard
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fleet: return "Fleet"
        case .inbox: return "Inbox"
        case .channels: return "Channels"
        case .director: return "Director"
        case .blackboard: return "Blackboard"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .fleet: return "circle.grid.3x3.fill"
        case .inbox: return "tray.fill"
        case .channels: return "bubble.left.and.bubble.right.fill"
        case .director: return "bolt.fill"
        case .blackboard: return "list.clipboard.fill"
        case .settings: return "gear"
        }
    }
}

/// Fleet inspector column mode — agent metadata vs inline DM thread.
enum FleetDetailMode: Equatable {
    case agent
    case dm
}

/// Channels inspector column — thread vs inline DM from mention/reply actions.
enum ChannelInspectorMode: Equatable {
    case thread
    case dm(agentName: String)
}

/// Shared selection state for the iPad 3-column command center shell.
@MainActor
final class CommandCenterState: ObservableObject {
    @Published var selectedDestination: CommandDestination = .fleet
    @Published var selectedAgentName: String?
    @Published var fleetDetailMode: FleetDetailMode = .agent
    @Published var selectedInboxSender: String?
    @Published var selectedChannelName: String?
    @Published var channelInspectorMode: ChannelInspectorMode = .thread
    @Published var channelDMReplyContext: ReplyContext?
    @Published var selectedBlackboardKey: String?
    @Published var phoneTab: PhoneTab = .fleet
    /// Bumped on each deep link so phone shell reacts even if tab unchanged.
    @Published var deepLinkEpoch: UInt = 0

    func selectAgent(_ agentName: String?) {
        selectedAgentName = agentName
        if agentName != nil {
            fleetDetailMode = .agent
        }
    }

    func openFleetDM(agentName: String) {
        selectedAgentName = agentName
        fleetDetailMode = .dm
    }

    func selectInboxSender(_ sender: String?) {
        selectedInboxSender = sender
    }

    func selectChannel(_ name: String?) {
        guard selectedChannelName != name || channelInspectorMode != .thread else { return }
        selectedChannelName = name
        channelInspectorMode = .thread
        channelDMReplyContext = nil
    }

    func openChannelDM(agentName: String, replyContext: ReplyContext? = nil) {
        channelInspectorMode = .dm(agentName: agentName)
        channelDMReplyContext = replyContext
    }

    func showChannelThread() {
        channelInspectorMode = .thread
        channelDMReplyContext = nil
    }

    func selectBlackboardKey(_ key: String?) {
        selectedBlackboardKey = key
    }

    func apply(route: DeepLinkRoute) {
        deepLinkEpoch &+= 1
        switch route {
        case .fleet(let agent):
            selectedDestination = .fleet
            phoneTab = .fleet
            openFleetDM(agentName: agent)
        case .inbox(let sender):
            selectedDestination = .inbox
            phoneTab = .inbox
            selectedInboxSender = sender
        case .channel(let name):
            selectedDestination = .channels
            phoneTab = .channels
            selectedChannelName = name
            channelInspectorMode = .thread
        }
    }

    /// Resolves the live fleet peer by agent name so the inspector stays current under SSE refresh.
    func selectedPeer(from fleetService: FleetService) -> Peer? {
        guard let name = selectedAgentName else { return nil }
        return peer(named: name, in: fleetService)
    }

    func peer(named agentName: String, in fleetService: FleetService) -> Peer {
        fleetService.peers.first { $0.agentName == agentName }
            ?? Peer(
                agentName: agentName,
                pid: nil,
                cwd: nil,
                gitRoot: nil,
                summary: nil,
                status: .offline
            )
    }
}