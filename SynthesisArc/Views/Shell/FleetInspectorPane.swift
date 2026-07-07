import SwiftUI

/// Third column — live agent detail resolved from fleetService by agentName.
struct FleetInspectorPane: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService

    private var peer: Peer? {
        commandCenterState.selectedPeer(from: fleetService)
    }

    var body: some View {
        Group {
            if let peer {
                switch commandCenterState.fleetDetailMode {
                case .agent:
                    AgentDetailView(
                        peer: peer,
                        usesInlineDM: true,
                        onOpenInlineDM: { commandCenterState.openFleetDM(agentName: peer.agentName) }
                    )
                case .dm:
                    DMView(
                        peer: peer,
                        draftKeyOverride: ComposerDraftStore.fleetDMKey(peer.agentName)
                    )
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Select an Agent",
            systemImage: "person.crop.circle.badge.questionmark",
            description: Text("Tap a fleet card to view status, quick actions, and blackboard details.")
        )
    }
}