import Foundation
import SwiftUI
import UserNotifications

// MARK: - App lifecycle (foreground gate for notifications)

/// Tracks whether the app is in the foreground so SSE events can suppress local alerts.
@MainActor
final class AppLifecycle: ObservableObject {
    static let shared = AppLifecycle()

    @Published private(set) var scenePhase: ScenePhase = .inactive

    var isForegroundActive: Bool { scenePhase == .active }

    func update(scenePhase: ScenePhase) {
        self.scenePhase = scenePhase
    }
}

// MARK: - Severity

enum NotificationSeverity {
    case crit
    case warn
    case info
}

// MARK: - Watchlist channels (INFO-tier channel messages)

enum ChannelWatchlist {
    static let storageKey = "channels.watchlist"
    static let defaultChannels: Set<String> = ["engineering", "ops"]

    static func decode(_ raw: String) -> Set<String> {
        guard !raw.isEmpty else { return defaultChannels }
        return Set(
            raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}

// MARK: - Push notification service

/// Local notifications driven by forge-graphd SSE when the app is backgrounded.
@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let lifecycle = AppLifecycle.shared

    private init() {}

    // MARK: - Permission

    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorizationStatus = granted ? .authorized : .denied
            print("[PushNotification] permission \(granted ? "granted" : "denied")")
        } catch {
            print("[PushNotification] permission error: \(error)")
        }
    }

    // MARK: - Event entry points

    func notifyDM(from: String, content: String) {
        guard shouldDeliver(severity: .warn) else { return }
        let preview = Self.truncate(content)
        deliver(
            identifier: "dm-\(from)-\(Date().timeIntervalSince1970)",
            title: "DM from \(from)",
            body: preview,
            severity: .warn,
            route: .inbox(sender: from)
        )
    }

    func notifyMention(channel: String, from: String, content: String) {
        guard shouldDeliver(severity: .warn) else { return }
        let preview = Self.truncate(content)
        deliver(
            identifier: "mention-\(channel)-\(from)-\(Date().timeIntervalSince1970)",
            title: "Mention in #\(channel)",
            body: "\(from): \(preview)",
            severity: .warn,
            route: .channel(name: channel)
        )
    }

    func notifyDegraded(agent: String, value: String) {
        guard shouldDeliver(severity: .crit) else { return }
        deliver(
            identifier: "degraded-\(agent)-\(Date().timeIntervalSince1970)",
            title: "Agent degraded",
            body: "\(agent): \(Self.truncate(value, max: 120))",
            severity: .crit,
            route: .fleet(agent: agent)
        )
    }

    func notifyChannel(channel: String, from: String, preview: String) {
        guard shouldDeliver(severity: .info) else { return }
        deliver(
            identifier: "channel-\(channel)-\(from)-\(Date().timeIntervalSince1970)",
            title: "#\(channel)",
            body: "\(from): \(Self.truncate(preview))",
            severity: .info,
            route: .channel(name: channel)
        )
    }

    // MARK: - Mention detection

    static func containsMention(of agentName: String, in content: String) -> Bool {
        MentionParser.segments(in: content).contains { segment in
            if case .mention(let text) = segment {
                return text == "@\(agentName)"
            }
            return false
        }
    }

    /// Channel reply header (`↩ msg/… @agent`) scoped to another agent — skip ambient watchlist alerts.
    static func isTargetedReplyToOtherAgent(in content: String, localAgent: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("↩") else { return false }
        let mentions = MentionParser.segments(in: content).compactMap { segment -> String? in
            if case .mention(let text) = segment { return text }
            return nil
        }
        guard let first = mentions.first else { return false }
        return first != "@\(localAgent)"
    }

    static func isDegradedBlackboardUpdate(key: String, value: String?) -> Bool {
        guard key.hasSuffix(".status"), let value else { return false }
        return value.localizedCaseInsensitiveContains("degraded")
    }

    static func isWatchlistChannel(_ channel: String) -> Bool {
        let raw = UserDefaults.standard.string(forKey: ChannelWatchlist.storageKey) ?? ""
        return ChannelWatchlist.decode(raw).contains(channel)
    }

    // MARK: - Private

    private func shouldDeliver(severity: NotificationSeverity) -> Bool {
        guard !lifecycle.isForegroundActive else { return false }

        let config = AppConfig.shared
        guard config.notificationsEnabled else { return false }

        switch severity {
        case .crit:
            return config.notificationsCritical
        case .warn, .info:
            return config.notificationsMessages
        }
    }

    private func deliver(
        identifier: String,
        title: String,
        body: String,
        severity: NotificationSeverity,
        route: DeepLinkRoute? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let route {
            content.userInfo = route.userInfo
        }

        switch severity {
        case .crit:
            content.sound = .default
        case .warn:
            content.sound = .default
        case .info:
            content.sound = nil
        }

        if #available(iOS 15.0, macOS 12.0, *) {
            switch severity {
            case .crit:
                content.interruptionLevel = .timeSensitive
            case .warn:
                content.interruptionLevel = .active
            case .info:
                content.interruptionLevel = .passive
            }
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("[PushNotification] deliver failed: \(error)")
            }
        }
    }

    private static func truncate(_ text: String, max: Int = 200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }
}