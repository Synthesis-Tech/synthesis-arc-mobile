import Foundation

/// Ring-buffer audit log for connection diagnostics — survives the session, not app restarts.
@MainActor
final class CoordinationAuditLog: ObservableObject {
    static let shared = CoordinationAuditLog()

    enum Category: String, CaseIterable {
        case lifecycle
        case sse
        case boot
        case channel
        case network
        case settings
    }

    enum Level: String {
        case info
        case warn
        case error

        var symbol: String {
            switch self {
            case .info: return "ℹ️"
            case .warn: return "⚠️"
            case .error: return "✗"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let level: Level
        let message: String

        var line: String {
            let time = Entry.timeFormatter.string(from: timestamp)
            return "[\(time)] \(level.symbol) \(category.rawValue): \(message)"
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f
        }()
    }

    @Published private(set) var entries: [Entry] = []
    /// Lines recovered from disk on last launch — survives force-quit.
    @Published private(set) var persistedLines: [String] = []

    private let capacity = 250
    private let persistedCapacity = 500
    private let logFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("coordination-audit.log")
    }()

    private init() {
        persistedLines = Self.readPersistedLines(from: logFileURL, limit: persistedCapacity)
    }

    func log(
        _ message: String,
        category: Category = .lifecycle,
        level: Level = .info
    ) {
        let entry = Entry(timestamp: Date(), category: category, level: level, message: message)
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        appendToDisk(entry.line)
        print("[Audit] \(entry.line)")
        UsabilityTrace.shared.ingestAudit(message: message, category: category, level: level)
    }

    func clear() {
        entries.removeAll()
        persistedLines.removeAll()
        try? FileManager.default.removeItem(at: logFileURL)
        log("Audit log cleared", category: .settings)
    }

    private func appendToDisk(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFileURL.path),
           let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    private static func readPersistedLines(from url: URL, limit: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(limit))
    }

    func exportText(
        fleetService: FleetService,
        streamService: CoordinationStreamService,
        channelService: ChannelService
    ) -> String {
        var lines: [String] = []
        lines.append("Forge Commander Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append(snapshotLines(
            fleetService: fleetService,
            streamService: streamService,
            channelService: channelService
        ).joined(separator: "\n"))
        lines.append("")
        if !persistedLines.isEmpty {
            lines.append("--- Persisted Log (survives force-quit, \(persistedLines.count) lines) ---")
            lines.append(contentsOf: persistedLines)
            lines.append("")
        }
        lines.append("--- Current Session (\(entries.count) entries) ---")
        for entry in entries.reversed() {
            lines.append(entry.line)
        }
        return lines.joined(separator: "\n")
    }

    func snapshotLines(
        fleetService: FleetService,
        streamService: CoordinationStreamService,
        channelService: ChannelService
    ) -> [String] {
        let config = AppConfig.shared
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let sseState = streamService.connectionStatusLabel

        let apiKeyStatus = config.apiKey.isEmpty ? "missing" : "set (\(config.apiKey.count) chars)"

        return [
            "App: Forge Commander \(version) (\(build))",
            "Graphd: \(config.graphdHost):\(config.graphdPort)",
            "Agent: \(config.agentName)",
            "API key: \(apiKeyStatus)",
            "Booted: \(fleetService.isBooted)",
            "Graphd healthy: \(fleetService.graphdHealthy)",
            "SSE: \(sseState)",
            "Peers: \(fleetService.peers.count)",
            "Channels listed: \(channelService.channels.count)",
            "Channel unread: \(channelService.totalChannelUnread)",
            "Inbox unread (SSE): \(streamService.unreadCount)",
            "Principal configured: \(PrincipalContext.shared.isConfigured)",
            "Peer ID: \(fleetService.myPeerId.map { String($0) } ?? "—")",
            "Session ID: \(fleetService.mySessionId.map { String($0) } ?? "—")",
            "Fleet error: \(fleetService.error ?? "none")",
            "SSE error: \(streamService.lastError ?? "none")",
            "Channel error: \(channelService.error ?? "none")",
            "Hot layer: \(CoordinationHotLayer.shared.statusLabel)"
        ]
    }
}