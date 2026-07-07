import Foundation
import SwiftUI

/// App configuration — forge-graphd connection, display preferences
@MainActor
class AppConfig: ObservableObject {
    static let shared = AppConfig()

    /// Graphd host — localhost for simulator; Tailscale IP for physical device
    /// (e.g. 100.123.250.101 gmktec-k9 always-on, 100.111.226.82 macbook-pro)
    @AppStorage("graphd.host") var graphdHost = "127.0.0.1"

    @AppStorage("graphd.port") var graphdPort = 9090

    /// Shared fleet API key (Authorization: ApiKey header)
    @AppStorage("graphd.apiKey") var apiKey = ""

    /// Caller identity (X-Agent-Id header) — human peer in the coordination graph
    @AppStorage("agent.name") var agentName = "daniel-willitzer"

    @AppStorage("polling.interval") var pollingInterval: Double = 30.0

    @AppStorage("fleet.showOffline") var showOfflineAgents = true

    @AppStorage("display.appearance") var appearanceRaw = AppAppearance.system.rawValue

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    /// Optional path to a synced roster JSON (macOS dev). Empty → bundled fleet-roster.json.
    @AppStorage("fleet.rosterPath") var fleetRosterPath = ""

    /// Optional ops-graph stats JSON URL (e.g. file:// or http://). Empty → posture card hidden.
    @AppStorage("opsGraph.statsURL") var opsGraphStatsURL = ""

    /// Automatic usability issue logging — structured events uploaded to graphd blackboard (no message text).
    @AppStorage("tracing.autoIssueLogging") var autoIssueLogging = true

    @AppStorage("notifications.enabled") var notificationsEnabled = true
    @AppStorage("notifications.critical") var notificationsCritical = true
    @AppStorage("notifications.messages") var notificationsMessages = true

    #if os(macOS)
    @AppStorage("menubar.enabled") var menuBarEnabled = true
    #endif

    var graphdBaseURL: URL {
        URL(string: "http://\(graphdHost):\(graphdPort)")!
    }

    func makeClient() -> ForgeGraphClient {
        ForgeGraphClient(
            host: graphdHost,
            port: graphdPort,
            apiKey: apiKey,
            agentId: agentName
        )
    }

    // Legacy keys migrated on first read
    init() {
        migrateLegacySettings()
        // Skip audit logging during singleton init — audit → UsabilityTrace → AppConfig deadlocks.
        applyE2EEnvironment(logToAudit: false)
    }

    /// Injects graphd credentials from launch environment (UI E2E harness / XCUITest).
    func applyE2EEnvironment(logToAudit: Bool = true) {
        let env = ProcessInfo.processInfo.environment
        guard env["FORGE_E2E"] == "1" || env["FORGE_GRAPH_API_KEY"] != nil else { return }
        if let host = env["FORGE_GRAPH_HOST"], !host.isEmpty { graphdHost = host }
        if let port = env["FORGE_GRAPH_PORT"], let value = Int(port) { graphdPort = value }
        if let key = env["FORGE_GRAPH_API_KEY"], !key.isEmpty { apiKey = key }
        if let agent = env["FORGE_GRAPH_AGENT"], !agent.isEmpty { agentName = agent }
        if logToAudit, env["FORGE_E2E"] == "1" {
            CoordinationAuditLog.shared.log(
                "E2E config applied — host \(graphdHost):\(graphdPort), agent \(agentName), key \(apiKey.isEmpty ? "missing" : "set")",
                category: .settings
            )
        }
    }

    private func migrateLegacySettings() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "graphd.host") == nil,
           let legacyHost = defaults.string(forKey: "daemon.host") {
            graphdHost = legacyHost
        }
        if defaults.object(forKey: "graphd.port") == nil,
           let legacyPort = defaults.object(forKey: "daemon.port") as? Int,
           legacyPort != 7899 {
            graphdPort = legacyPort
        } else if defaults.object(forKey: "graphd.port") == nil {
            graphdPort = 9090
        }
    }
}

struct SettingsView: View {
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

                Text("Re-boots your peer session and restarts the SSE stream with the settings above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Forge Graph Connection") {
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
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTesting ? "Testing..." : "Test Connection")
                    }
                }
                .disabled(isTesting || config.apiKey.isEmpty)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("OK") ? .green : .red)
                }
            }

            Section("Notifications") {
                Toggle("Enable Notifications", isOn: $config.notificationsEnabled)

                Toggle("Critical (degraded agents)", isOn: $config.notificationsCritical)
                    .disabled(!config.notificationsEnabled)

                Toggle("Messages (DMs, mentions, channels)", isOn: $config.notificationsMessages)
                    .disabled(!config.notificationsEnabled)

                Text("Local alerts when the app is in the background. No push server required.")
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

            Section("Advanced") {
                TextField("Ops Graph stats URL", text: $config.opsGraphStatsURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                Text("JSON with repos, violations, deadCode — e.g. file:///path/stats.json or http://host/stats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Toggle("Automatic issue logging", isOn: $config.autoIssueLogging)
                Text("Logs usability events and errors automatically. Uploads to graphd blackboard — never includes message text or API keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    DiagnosticsPanelView()
                } label: {
                    Label("Connection Diagnostics", systemImage: "waveform.path.ecg")
                }
                Text("Live status, config snapshot, and session audit log for troubleshooting.")
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
        .frame(minWidth: 400)
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
