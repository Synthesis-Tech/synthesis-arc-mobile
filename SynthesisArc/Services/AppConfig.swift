import Foundation
import SwiftUI

/// App configuration — daemon connection, display preferences
/// Persists to UserDefaults with @AppStorage compatibility
@MainActor
class AppConfig: ObservableObject {
    static let shared = AppConfig()

    /// Daemon host — Tailscale IP of the machine running agent-hooks
    @AppStorage("daemon.host") var daemonHost = "100.111.226.82"

    /// Daemon port
    @AppStorage("daemon.port") var daemonPort = 7899

    /// Polling interval in seconds (replaced by SSE in Phase 2)
    @AppStorage("polling.interval") var pollingInterval: Double = 10.0

    /// Show offline agents in fleet view
    @AppStorage("fleet.showOffline") var showOfflineAgents = true

    /// macOS: show menu bar extra
    @AppStorage("menubar.enabled") var menuBarEnabled = true

    /// Daemon base URL computed from host + port
    var daemonBaseURL: URL {
        URL(string: "http://\(daemonHost):\(daemonPort)")!
    }
}

/// Settings view for configuring daemon connection
struct SettingsView: View {
    @ObservedObject var config = AppConfig.shared
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Daemon Connection") {
                TextField("Host (Tailscale IP)", text: $config.daemonHost)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $config.daemonPort, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

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
                .disabled(isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("OK") ? .green : .red)
                }
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
                Toggle("Menu Bar Widget", isOn: $config.menuBarEnabled)
                #endif
            }

            Section("About") {
                LabeledContent("App", value: "Synthesis Arc Fleet")
                LabeledContent("Phase", value: "1 — Fleet + Channels")
                LabeledContent("Transport", value: "Tailscale → Daemon :7899")
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

        let daemon = DaemonClient(
            host: config.daemonHost,
            port: config.daemonPort
        )

        do {
            let healthy = try await daemon.health()
            testResult = healthy ? "✓ Daemon OK" : "✗ Daemon unhealthy"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }

        isTesting = false
    }
}
