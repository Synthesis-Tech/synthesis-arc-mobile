import SwiftUI

/// Director ops summary column — broadcast form lives in the inspector column.
struct DirectorCommandCenterView: View {
    @StateObject private var opsGraphService = OpsGraphService()

    var body: some View {
        Form {
            Section("Ops Graph Posture") {
                if opsGraphService.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading fleet posture…")
                            .foregroundStyle(.secondary)
                    }
                } else if let posture = opsGraphService.posture {
                    Label(posture.summaryLine, systemImage: "chart.bar.doc.horizontal")
                    if let deadCodeLine = posture.deadCodeLine {
                        Text(deadCodeLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Configure Ops Graph stats URL in Settings → Advanced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = opsGraphService.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Director") {
                Text("Fleet-wide broadcasts post to #engineering and/or #ops. Use the inspector column to compose and send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("Director")
        .refreshable { _ = await opsGraphService.fetchFleetPosture() }
        .task { _ = await opsGraphService.fetchFleetPosture() }
    }
}

struct DirectorInspectorPane: View {
    @StateObject private var broadcastService = BroadcastService()
    @State private var message = ""
    @State private var target: DirectorBroadcastTarget = .both
    @State private var isSending = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Broadcast Target") {
                Picker("Target", selection: $target) {
                    ForEach(DirectorBroadcastTarget.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            }

            Section("Message") {
                TextField("Fleet-wide message", text: $message, axis: .vertical)
                    .lineLimit(4...12)

                Button {
                    Task { await sendBroadcast() }
                } label: {
                    HStack {
                        if isSending {
                            ProgressView().controlSize(.small)
                        }
                        Label(isSending ? "Sending…" : "Send Broadcast", systemImage: "bolt.fill")
                    }
                }
                .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusMessage.contains("✓") ? .green : .red)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendBroadcast() async {
        isSending = true
        statusMessage = nil
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSending = false
            return
        }

        do {
            switch target {
            case .engineering:
                try await broadcastService.broadcast(channel: "engineering", content: trimmed)
            case .ops:
                try await broadcastService.broadcast(channel: "ops", content: trimmed)
            case .both:
                try await broadcastService.broadcastToWatchlistChannels(content: trimmed)
            }
            message = ""
            statusMessage = "✓ Broadcast sent"
        } catch {
            statusMessage = "✗ \(error.localizedDescription)"
        }
        isSending = false
    }
}