import SwiftUI

enum ChannelInviteCopy {
    static func dmBody(channel: Channel, inviter: String) -> String {
        var lines = [
            "You're invited to #\(channel.name) by \(inviter).",
            "",
            "In Forge Commander: open Channels → #\(channel.name).",
        ]
        if channel.visibility == .private {
            lines.append("This channel is private — tap Join #\(channel.name) when you open it.")
        } else {
            lines.append("It's a public channel — you can read and post once you open the thread.")
        }
        if let description = channel.description, !description.isEmpty {
            lines.append("")
            lines.append("About: \(description)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Pick fleet peers and invite them to a channel via bilateral DM.
struct ChannelInviteSheet: View {
    let channel: Channel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var dmService: DMService

    @State private var searchText = ""
    @State private var inFlight: Set<String> = []
    @State private var sentTo: Set<String> = []
    @State private var errors: [String: String] = [:]

    private var inviterName: String {
        PrincipalContext.shared.localAgentName
    }

    private var inviteMessage: String {
        ChannelInviteCopy.dmBody(channel: channel, inviter: inviterName)
    }

    private var candidates: [Peer] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return fleetService.peers
            .deduplicatedByAgent()
            .filter { $0.agentName != inviterName }
            .filter { peer in
                guard !needle.isEmpty else { return true }
                return peer.agentName.localizedCaseInsensitiveContains(needle)
                    || AgentMentionAutocomplete.displayLabel(for: peer.agentName)
                        .localizedCaseInsensitiveContains(needle)
            }
            .sorted { $0.agentName.localizedCaseInsensitiveCompare($1.agentName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Fleet Peers" : "No Matches",
                        systemImage: "person.2",
                        description: Text(searchText.isEmpty
                            ? "Fleet peers appear after forge-graphd boots."
                            : "Try a different search term.")
                    )
                } else {
                    List(candidates) { peer in
                        inviteRow(for: peer)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Invite to #\(channel.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search fleet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                invitePreview
            }
        }
    }

    private var invitePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DM preview")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(inviteMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func inviteRow(for peer: Peer) -> some View {
        HStack(spacing: 12) {
            AgentAvatarView(agentName: peer.agentName, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(AgentMentionAutocomplete.displayLabel(for: peer.agentName))
                    .font(.body.bold())
                Text(peer.agentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let summary = peer.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            inviteButton(for: peer)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func inviteButton(for peer: Peer) -> some View {
        let name = peer.agentName

        if sentTo.contains(name) {
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else if inFlight.contains(name) {
            ProgressView()
                .controlSize(.small)
        } else if let err = errors[name] {
            VStack(alignment: .trailing, spacing: 4) {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                Button("Retry") {
                    Task { await sendInvite(to: name) }
                }
                .font(.caption.bold())
            }
        } else {
            Button {
                Task { await sendInvite(to: name) }
            } label: {
                Label("Invite", systemImage: "paperplane.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
        }
    }

    private func sendInvite(to agentName: String) async {
        guard !inFlight.contains(agentName) else { return }
        inFlight.insert(agentName)
        errors.removeValue(forKey: agentName)

        let client = AppConfig.shared.makeClient()
        let optimistic = dmService.makeOptimisticOutbound(to: agentName, content: inviteMessage)
        dmService.appendOutbound(optimistic)

        do {
            if let serverId = try await client.sendDM(to: agentName, content: inviteMessage) {
                dmService.confirmOutbound(
                    optimisticId: optimistic.id,
                    serverId: serverId,
                    to: agentName,
                    content: inviteMessage
                )
            }
            sentTo.insert(agentName)
            CoordinationAuditLog.shared.log(
                "Channel invite DM sent — #\(channel.name) → @\(agentName)",
                category: .channel
            )
        } catch {
            errors[agentName] = error.localizedDescription
            CoordinationAuditLog.shared.log(
                "Channel invite DM failed — #\(channel.name) → @\(agentName): \(error.localizedDescription)",
                category: .channel,
                level: .error
            )
        }

        inFlight.remove(agentName)
    }
}