import SwiftUI

enum DirectorBroadcastTarget: String, CaseIterable, Identifiable {
    case engineering
    case ops
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .engineering: return "#engineering"
        case .ops: return "#ops"
        case .both: return "Both (#engineering + #ops)"
        }
    }
}

/// Director console — fleet-wide broadcasts and ops-graph posture.
struct DirectorConsoleView: View {
    @StateObject private var broadcastService = BroadcastService()
    @StateObject private var opsGraphService = OpsGraphService()

    @State private var message = ""
    @State private var target: DirectorBroadcastTarget = .both
    @State private var isSending = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ops Graph") {
                    if opsGraphService.isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
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
                        Text("Configure Ops Graph stats URL in Settings → Advanced to show fleet code posture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let err = opsGraphService.error {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Broadcast") {
                    Picker("Target", selection: $target) {
                        ForEach(DirectorBroadcastTarget.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(4...12)

                    Button {
                        Task { await sendBroadcast() }
                    } label: {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(isSending ? "Sending…" : "Send Broadcast", systemImage: "bolt.fill")
                        }
                    }
                    .disabled(isSending || trimmedMessage.isEmpty)
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
            .refreshable {
                _ = await opsGraphService.fetchFleetPosture()
            }
            .task {
                _ = await opsGraphService.fetchFleetPosture()
            }
        }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendBroadcast() async {
        let content = trimmedMessage
        guard !content.isEmpty else { return }

        isSending = true
        statusMessage = nil
        broadcastService.error = nil
        defer { isSending = false }

        do {
            switch target {
            case .engineering:
                try await broadcastService.broadcast(channel: "engineering", content: content)
                statusMessage = "Sent to #engineering"
            case .ops:
                try await broadcastService.broadcast(channel: "ops", content: content)
                statusMessage = "Sent to #ops"
            case .both:
                try await broadcastService.broadcastToWatchlistChannels(content: content)
                statusMessage = "Sent to #engineering and #ops"
            }
            message = ""
        } catch {
            statusMessage = "Broadcast failed: \(error.localizedDescription)"
        }
    }
}