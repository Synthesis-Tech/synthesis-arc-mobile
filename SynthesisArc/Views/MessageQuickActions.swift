import SwiftUI

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Clipboard

enum FleetClipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Avatar

struct AgentAvatarView: View {
    let agentName: String
    var size: CGFloat = 36

    private var initials: String {
        let parts = agentName.split(separator: "-")
        return parts.prefix(2).map { String($0.prefix(1).uppercased()) }.joined()
    }

    private var tint: Color {
        let hash = agentName.utf8.reduce(0) { $0 &+ Int($1) }
        let hues: [Color] = [.blue, .purple, .teal, .indigo, .cyan, .mint]
        return hues[abs(hash) % hues.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(agentName)
    }
}

// MARK: - Quick action chip (agent profile / fleet)

struct QuickActionChip: View {
    let title: String
    let icon: String
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message hover / inline action bar (Slack-style)

struct MessageActionBar: View {
    var onReply: (() -> Void)?
    var onDM: (() -> Void)?
    var onMention: (() -> Void)?
    var onCopyRef: (() -> Void)?
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            if let onReply {
                messageActionButton(
                    label: "Reply",
                    icon: "arrowshape.turn.up.left",
                    tint: .cyan,
                    action: onReply
                )
            }
            if let onMention {
                messageActionButton(
                    label: "Mention",
                    icon: "at",
                    tint: .blue,
                    action: onMention
                )
            }
            if let onDM {
                messageActionButton(
                    label: "DM",
                    icon: "envelope",
                    tint: .indigo,
                    action: onDM
                )
            }
            if let onCopyRef {
                messageActionButton(
                    label: "Copy ref",
                    icon: "number",
                    tint: .secondary,
                    action: onCopyRef
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(emphasized ? 0.12 : 0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(emphasized ? 0.12 : 0.06), radius: emphasized ? 4 : 2, y: 1)
        .animation(.easeOut(duration: 0.15), value: emphasized)
    }

    private func messageActionButton(
        label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 26)
                .background(tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Channel header strip

struct ChannelHeaderBar: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: channel.visibility == .private ? "lock.fill" : "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("#\(channel.name)")
                    .font(.headline)
                Text("\(channel.memberCount) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                Spacer()
            }
            if let description = channel.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.04))
    }
}

// MARK: - Agent quick actions panel

struct AgentQuickActionsPanel: View {
    let peer: Peer
    var onDM: () -> Void
    var onMention: () -> Void
    var onCopyID: () -> Void
    var onDirector: () -> Void

    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var fleetService: FleetService

    @State private var opsDraft = ""
    @State private var statusDraft = ""
    @State private var isWorking = false
    @State private var feedback: String?

    private var statusKey: String { "\(peer.agentName).status" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Quick Actions", systemImage: "bolt.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                QuickActionChip(title: "DM", icon: "envelope.fill", tint: .indigo, action: onDM)
                QuickActionChip(title: "Mention", icon: "at", tint: .blue, action: onMention)
                QuickActionChip(title: "Copy ID", icon: "doc.on.doc", tint: .secondary, action: onCopyID)
                QuickActionChip(title: "#engineering", icon: "number", tint: .cyan) {
                    let mention = "@\(peer.agentName)"
                    FleetClipboard.copy(mention)
                    opsDraft = "\(mention) "
                    feedback = "Copied \(mention) — finish in #ops below or paste in Channels"
                }
                QuickActionChip(title: "#ops", icon: "megaphone.fill", tint: .orange) {
                    opsDraft = "@\(peer.agentName) "
                    feedback = "Draft ready — add ops update and tap Post"
                }
                QuickActionChip(title: "Director", icon: "person.badge.key.fill", tint: .purple, action: onDirector)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Post to #ops")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ops update for fleet…", text: $opsDraft, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Button("Post") {
                        Task { await postOps() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isWorking || opsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(statusKey)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Blackboard status", text: $statusDraft, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        Task { await setStatus() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isWorking || statusDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            if statusDraft.isEmpty {
                statusDraft = peer.blackboardStatus ?? ""
            }
        }
    }

    private func postOps() async {
        let content = opsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isWorking = true
        feedback = nil
        defer { isWorking = false }
        await channelService.send(channel: "ops", content: content)
        if let err = channelService.error {
            feedback = err
        } else {
            opsDraft = ""
            feedback = "Posted to #ops"
        }
    }

    private func setStatus() async {
        let value = statusDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isWorking = true
        feedback = nil
        defer { isWorking = false }
        let client = AppConfig.shared.makeClient()
        do {
            try await client.setBlackboard(key: statusKey, value: value)
            fleetService.applyBlackboardUpdate(
                key: statusKey,
                value: value,
                setBy: AppConfig.shared.agentName,
                timestamp: Int64(Date().timeIntervalSince1970)
            )
            feedback = "Blackboard updated"
        } catch {
            feedback = error.localizedDescription
        }
    }
}