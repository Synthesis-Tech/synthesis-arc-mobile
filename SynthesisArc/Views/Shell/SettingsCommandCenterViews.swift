import SwiftUI

/// Settings center column — connection + apply/reconnect (spec: connection form content).
struct SettingsConnectionFormView: View {
    @ObservedObject var config = AppConfig.shared
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var streamService: CoordinationStreamService
    @EnvironmentObject var channelService: ChannelService
    @EnvironmentObject var dmService: DMService
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isReconnecting = false
    @State private var reconnectResult: String?

    var body: some View {
        Form {
            Section("Connection") {
                Button {
                    Task { await applyAndReconnect() }
                } label: {
                    HStack {
                        if isReconnecting {
                            ProgressView().controlSize(.small)
                        }
                        Text(isReconnecting ? "Reconnecting…" : "Apply & Reconnect")
                    }
                }
                .disabled(isReconnecting || config.apiKey.isEmpty)

                if let reconnectResult {
                    Text(reconnectResult)
                        .font(.caption)
                        .foregroundStyle(reconnectResult.contains("✓") ? .green : .red)
                }
            }

            Section("Forge Graph") {
                TextField("Host (Tailscale IP)", text: $config.graphdHost)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $config.graphdPort, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                SecureField("API Key", text: $config.apiKey)
                    .textContentType(.password)

                TextField("Agent ID (X-Agent-Id)", text: $config.agentName)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text(isTesting ? "Testing..." : "Test Connection")
                    }
                }
                .disabled(isTesting || config.apiKey.isEmpty)

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.contains("OK") ? .green : .red)
                }
            }

            Section("Diagnostics") {
                Toggle("Automatic issue logging", isOn: $config.autoIssueLogging)
                NavigationLink {
                    DiagnosticsPanelView()
                } label: {
                    Label("Connection Diagnostics", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier(E2EAccessibility.settingsDiagnostics)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("Settings")
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let client = config.makeClient()
        do {
            let healthy = try await client.health()
            guard healthy else {
                testResult = "✗ Graphd unhealthy"
                isTesting = false
                return
            }
            let peers = try await client.listPeers()
            let sseStatus = streamService.connectionStatusLabel
            testResult = "✓ Graphd OK — \(peers.count) peers, \(sseStatus)"
            CoordinationAuditLog.shared.log(
                "Connection test OK — \(peers.count) peers, \(sseStatus)",
                category: .settings
            )
        } catch {
            testResult = "✗ \(error.localizedDescription)"
            CoordinationAuditLog.shared.log(
                "Connection test failed: \(error.localizedDescription)",
                category: .settings,
                level: .error
            )
        }
        isTesting = false
    }

    private func applyAndReconnect() async {
        isReconnecting = true
        reconnectResult = nil
        await fleetService.applySettingsAndReconnect(
            streamService: streamService,
            channelService: channelService,
            dmService: dmService
        )
        let sseLive = await streamService.waitForConnection(timeout: 30)
        reconnectResult = Self.reconnectSummary(isBooted: fleetService.isBooted, sseLive: sseLive)
        CoordinationAuditLog.shared.log(
            "Apply & Reconnect finished — \(reconnectResult ?? "unknown")",
            category: .settings,
            level: reconnectResult?.contains("✓") == true ? .info : .warn
        )
        isReconnecting = false
    }

    private static func reconnectSummary(isBooted: Bool, sseLive: Bool) -> String {
        if isBooted && sseLive {
            return "✓ Live — booted and SSE connected"
        }
        if isBooted {
            return "⚠ Booted but SSE still connecting — REST polling active"
        }
        return "✗ Reconnect finished but boot may have failed"
    }
}

/// Settings inspector column — notifications, display, advanced, about (spec: prefs detail).
struct SettingsPreferencesPane: View {
    @ObservedObject var config = AppConfig.shared

    var body: some View {
        NavigationStack {
            preferencesForm
        }
    }

    private var preferencesForm: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable Notifications", isOn: $config.notificationsEnabled)
                Toggle("Critical (degraded agents)", isOn: $config.notificationsCritical)
                    .disabled(!config.notificationsEnabled)
                Toggle("Messages (DMs, mentions, channels)", isOn: $config.notificationsMessages)
                    .disabled(!config.notificationsEnabled)
                Text("Local alerts when backgrounded. SSE reconnects on foreground.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AppearancePickerSection(selection: Binding(
                get: { config.appearance },
                set: { config.appearance = $0 }
            ))

            Section("Display") {
                HStack {
                    Text("Polling Interval")
                    Spacer()
                    Text("\(Int(config.pollingInterval))s")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $config.pollingInterval, in: 5...60, step: 5)
                Toggle("Show Offline Agents", isOn: $config.showOfflineAgents)
                #if os(macOS)
                TextField("Roster path (optional)", text: $config.fleetRosterPath)
                Toggle("Menu Bar Widget", isOn: $config.menuBarEnabled)
                #endif
            }

            Section("Diagnostics") {
                Toggle("Automatic issue logging", isOn: $config.autoIssueLogging)
                NavigationLink {
                    DiagnosticsPanelView()
                } label: {
                    Label("Connection Diagnostics", systemImage: "waveform.path.ecg")
                }
                Text("Live status, config snapshot, and session audit log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                TextField("Ops Graph stats URL", text: $config.opsGraphStatsURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Text("JSON with repos, violations, deadCode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: "Forge Commander")
                LabeledContent("Phase", value: "L4 — Director Console")
                LabeledContent("Backend", value: "forge-graphd :9090")
                LabeledContent("Transport", value: "Tailscale → /api/v1")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Preferences")
    }
}