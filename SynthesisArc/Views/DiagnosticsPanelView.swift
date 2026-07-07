import SwiftUI

/// Connection diagnostics + session audit log for field troubleshooting.
struct DiagnosticsPanelView: View {
    @ObservedObject private var auditLog = CoordinationAuditLog.shared
    @ObservedObject private var trace = UsabilityTrace.shared
    @ObservedObject private var hotLayer = CoordinationHotLayer.shared
    @ObservedObject private var config = AppConfig.shared
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var channelService: ChannelService

    @State private var copiedNotice = false

    var body: some View {
        List {
            statusSection
            tracingSection
            configSection
            auditSection
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Copy Report") {
                    FleetClipboard.copy(auditLog.exportText(
                        fleetService: fleetService,
                        streamService: streamService,
                        channelService: channelService
                    ))
                    copiedNotice = true
                }
                .accessibilityIdentifier(E2EAccessibility.diagnosticsCopy)
                Button("Clear Log", role: .destructive) {
                    auditLog.clear()
                }
                Button("Upload Issues Now") {
                    Task { await FieldReportUploader.shared.flushPending() }
                }
                .disabled(!config.autoIssueLogging)
            }
        }
        .alert("Copied", isPresented: $copiedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Diagnostics report copied to clipboard.")
        }
    }

    private var statusSection: some View {
        Section("Live Status") {
            statusRow("Graphd", value: fleetService.graphdHealthy ? "Healthy" : "Unreachable", ok: fleetService.graphdHealthy)
            statusRow("Boot", value: fleetService.isBooted ? "Booted" : "Not booted", ok: fleetService.isBooted)
            statusRow("Hot layer", value: hotLayer.isRunning ? "REST poll active" : "Idle", ok: hotLayer.isRunning)
            statusRow("SSE", value: sseStatusLabel, ok: streamService.isConnected)
            if let lastPoll = hotLayer.lastPollAt {
                LabeledContent("Last REST poll", value: lastPoll.formatted(date: .omitted, time: .standard))
            }
            LabeledContent("Poll ticks", value: "\(hotLayer.pollCount)")
            LabeledContent("Peers", value: "\(fleetService.peers.count)")
            LabeledContent("Channels", value: "\(channelService.channels.count)")
            LabeledContent("Inbox unread", value: "\(streamService.unreadCount)")

            if let peerId = fleetService.myPeerId {
                LabeledContent("Peer ID", value: String(peerId))
            }
            if let sessionId = fleetService.mySessionId {
                LabeledContent("Session ID", value: String(sessionId))
            }
            if let err = fleetService.error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let err = streamService.lastError {
                Text("SSE: \(err)").font(.caption).foregroundStyle(.orange)
            }
            if let err = channelService.error {
                Text("Channels: \(err)").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var tracingSection: some View {
        Section("Automatic Issue Logging") {
            Toggle("Enabled", isOn: $config.autoIssueLogging)
            LabeledContent(
                "Pending upload",
                value: "\(trace.pendingIssues.filter(\.isPendingUpload).count)"
            )
            if let lastUpload = trace.lastUploadAt {
                LabeledContent("Last upload", value: lastUpload.formatted(date: .abbreviated, time: .standard))
            }
            if let uploadError = trace.lastUploadError {
                Text(uploadError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if trace.pendingIssues.isEmpty {
                Text("No issues recorded this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trace.pendingIssues.prefix(8)) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(issue.signature)
                                .font(.caption.bold().monospaced())
                            Spacer()
                            Text(issue.uploadedAt == nil ? "pending" : "uploaded")
                                .font(.caption2)
                                .foregroundStyle(issue.uploadedAt == nil ? .orange : .green)
                        }
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Text("Reports go to graphd blackboard under ops/field-trace/… — usability events only, no message text.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var configSection: some View {
        Section("Connection Config") {
            let config = AppConfig.shared
            LabeledContent("Host", value: "\(config.graphdHost):\(config.graphdPort)")
            LabeledContent("Agent", value: config.agentName)
            LabeledContent("API Key", value: config.apiKey.isEmpty ? "Not set" : "•••••••• (\(config.apiKey.count) chars)")
            LabeledContent("Principal", value: PrincipalContext.shared.isConfigured ? "Configured" : "Pending boot")
            LabeledContent("App build", value: appBuildLabel)
        }
    }

    @ViewBuilder
    private var auditSection: some View {
        Section("Persisted Log (survives force-quit)") {
            if auditLog.persistedLines.isEmpty {
                Text("No persisted events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(auditLog.persistedLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }

        Section("Current Session (\(auditLog.entries.count))") {
            if auditLog.entries.isEmpty {
                Text("No events yet — open the app, connect, or use Apply & Reconnect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(auditLog.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.level.symbol)
                            Text(entry.category.rawValue.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(categoryColor(entry.category))
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var sseStatusLabel: String {
        if streamService.isConnected { return "Live (SSE + REST)" }
        if streamService.isPendingConnection { return "Connecting (REST already live)" }
        if streamService.lastError != nil { return "Unavailable (REST covers)" }
        return "Optional (REST primary)"
    }

    private var appBuildLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    @ViewBuilder
    private func statusRow(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(ok ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryColor(_ category: CoordinationAuditLog.Category) -> Color {
        switch category {
        case .sse: return .blue
        case .boot: return .purple
        case .channel: return .cyan
        case .network: return .orange
        case .settings: return .indigo
        case .lifecycle: return .secondary
        }
    }
}