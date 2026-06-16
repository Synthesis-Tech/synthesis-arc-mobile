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

    /// Optional path to a synced roster JSON (macOS dev). Empty → bundled fleet-roster.json.
    @AppStorage("fleet.rosterPath") var fleetRosterPath = ""

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
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
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

            Section("About") {
                LabeledContent("App", value: "Synthesis Arc Fleet")
                LabeledContent("Phase", value: "1 — Fleet + Channels")
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
            if healthy {
                _ = try await client.boot(summary: "\(config.agentName) — connection test")
                testResult = "✓ Graphd OK — boot succeeded"
            } else {
                testResult = "✗ Graphd unhealthy"
            }
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }

        isTesting = false
    }
}