import SwiftUI

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Director quick actions — DM, #ops post, blackboard status, copy agent ID.
struct QuickActionsSheet: View {
    let peer: Peer

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var fleetService: FleetService

    @State private var blackboardStatus = ""
    @State private var opsMessage = ""
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var copied = false

    private var statusKey: String { "\(peer.agentName).status" }

    var body: some View {
        NavigationStack {
            List {
                Section("Communicate") {
                    NavigationLink {
                        DMView(peer: peer)
                    } label: {
                        Label("Send DM", systemImage: "envelope.fill")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Message for #ops", text: $opsMessage, axis: .vertical)
                            .lineLimit(3...6)
                        Button {
                            Task { await postToOps() }
                        } label: {
                            Label("Post to #ops", systemImage: "megaphone.fill")
                        }
                        .disabled(
                            isWorking
                                || opsMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }

                Section("Blackboard") {
                    TextField("Status value", text: $blackboardStatus, axis: .vertical)
                        .lineLimit(2...4)
                        .onAppear {
                            if blackboardStatus.isEmpty {
                                blackboardStatus = peer.blackboardStatus ?? ""
                            }
                        }
                    Button {
                        Task { await setBlackboardStatus() }
                    } label: {
                        Label("Set \(statusKey)", systemImage: "list.clipboard")
                    }
                    .disabled(
                        isWorking
                            || blackboardStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                Section("Identity") {
                    LabeledContent("Agent ID", value: peer.agentName)
                    Button {
                        copyAgentID()
                    } label: {
                        Label(copied ? "Copied!" : "Copy Agent ID", systemImage: "doc.on.doc")
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Director")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func postToOps() async {
        let content = opsMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        await channelService.send(channel: "ops", content: content)
        if let err = channelService.error {
            statusMessage = "Post failed: \(err)"
        } else {
            opsMessage = ""
            statusMessage = "Posted to #ops"
        }
    }

    private func setBlackboardStatus() async {
        let value = blackboardStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        isWorking = true
        statusMessage = nil
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
            statusMessage = "Blackboard updated"
        } catch {
            statusMessage = "Blackboard failed: \(error.localizedDescription)"
        }
    }

    private func copyAgentID() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(peer.agentName, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = peer.agentName
        #endif
        copied = true
    }
}