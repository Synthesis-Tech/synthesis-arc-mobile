import Foundation

/// True when XCUITest launches the app with `FORGE_E2E=1` in launch environment.
enum E2EMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["FORGE_E2E"] == "1"
    }
}

/// Accessibility identifiers for UI E2E automation (XCUITest + agent harness).
enum E2EAccessibility {
    static let navPrefix = "nav."
    static func nav(_ destination: String) -> String { "nav.\(destination.lowercased())" }

    static let channelsCreate = "channels.create"
    static let channelsList = "channels.list"
    static func channelRow(_ name: String) -> String { "channel.row.\(name)" }
    static let channelJoin = "channel.join"
    static let channelComposer = "channel.composer"
    static let channelThread = "channel.thread"

    static let settingsDiagnostics = "settings.diagnostics"
    static let diagnosticsCopy = "diagnostics.copy"
    static let diagnosticsPanel = "diagnostics.panel"
    static let bootStatus = "boot.status"
}