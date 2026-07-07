import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Usability + reliability tracing — structured events and automatic issue detection.
/// Never captures message bodies, API keys, or other secrets.
@MainActor
final class UsabilityTrace: ObservableObject {
    static let shared = UsabilityTrace()

    enum Severity: String, Codable {
        case info
        case warn
        case error
    }

    struct TraceEvent: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let name: String
        let context: [String: String]

        init(name: String, context: [String: String] = [:]) {
            self.id = UUID()
            self.timestamp = Date()
            self.name = name
            self.context = context
        }
    }

    struct PendingIssue: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let signature: String
        let severity: Severity
        let message: String
        let context: [String: String]
        var uploadedAt: Date?

        var isPendingUpload: Bool { uploadedAt == nil }
    }

    @Published private(set) var recentEvents: [TraceEvent] = []
    @Published private(set) var pendingIssues: [PendingIssue] = []
    @Published private(set) var lastUploadAt: Date?
    @Published private(set) var lastUploadError: String?

    private struct ActiveSpan {
        let name: String
        let startedAt: Date
        let context: [String: String]
        let timeoutSeconds: TimeInterval
    }

    private var activeSpans: [UUID: ActiveSpan] = [:]
    private var watchdogTask: Task<Void, Never>?
    private let eventCapacity = 200
    private let issueCapacity = 50
    private let persistenceURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SynthesisArc", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usability-trace.json")
    }()

    private init() {
        loadFromDisk()
        startWatchdog()
    }

    // MARK: - Public API

    func trace(_ name: String, context: [String: String] = [:]) {
        guard AppConfig.shared.autoIssueLogging else { return }
        let event = TraceEvent(name: name, context: sanitize(context))
        recentEvents.insert(event, at: 0)
        if recentEvents.count > eventCapacity {
            recentEvents.removeLast(recentEvents.count - eventCapacity)
        }
        persist()
        print("[Trace] \(name) \(sanitize(context))")
    }

    @discardableResult
    func beginSpan(
        _ name: String,
        context: [String: String] = [:],
        timeoutSeconds: TimeInterval = 30
    ) -> UUID {
        let id = UUID()
        activeSpans[id] = ActiveSpan(
            name: name,
            startedAt: Date(),
            context: sanitize(context),
            timeoutSeconds: timeoutSeconds
        )
        trace("\(name).start", context: context)
        return id
    }

    func endSpan(_ id: UUID, outcome: String = "ok", extra: [String: String] = [:]) {
        guard let span = activeSpans.removeValue(forKey: id) else { return }
        let durationMs = Int(Date().timeIntervalSince(span.startedAt) * 1000)
        var context = span.context
        context["duration_ms"] = String(durationMs)
        context["outcome"] = outcome
        for (key, value) in extra { context[key] = value }
        trace("\(span.name).end", context: context)
    }

    func recordIssue(
        signature: String,
        message: String,
        severity: Severity = .error,
        context: [String: String] = [:]
    ) {
        guard AppConfig.shared.autoIssueLogging else { return }
        guard !E2EMode.isActive else { return }

        let issue = PendingIssue(
            id: UUID(),
            timestamp: Date(),
            signature: signature,
            severity: severity,
            message: message,
            context: sanitize(context),
            uploadedAt: nil
        )
        pendingIssues.insert(issue, at: 0)
        if pendingIssues.count > issueCapacity {
            pendingIssues.removeLast(pendingIssues.count - issueCapacity)
        }
        trace("issue.\(signature)", context: ["severity": severity.rawValue])
        persist()
        FieldReportUploader.shared.scheduleFlush()
    }

    func markIssueUploaded(_ id: UUID) {
        guard let index = pendingIssues.firstIndex(where: { $0.id == id }) else { return }
        pendingIssues[index].uploadedAt = Date()
        persist()
    }

    func noteUploadResult(at date: Date, error: String?) {
        lastUploadAt = date
        lastUploadError = error
    }

    func deviceContext() -> [String: String] {
        var context: [String: String] = [:]
        #if os(iOS)
        context["platform"] = "ios"
        context["device"] = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #elseif os(macOS)
        context["platform"] = "macos"
        context["device"] = "mac"
        #else
        context["platform"] = "unknown"
        #endif
        return context
    }

    func appContext() -> [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return [
            "app": "forge-commander",
            "version": version,
            "build": build
        ]
    }

    func auditTail(limit: Int = 40) -> [String] {
        let sessionLines = Array(CoordinationAuditLog.shared.entries.prefix(20)).map(\.line).reversed()
        let persisted = Array(CoordinationAuditLog.shared.persistedLines.suffix(limit))
        return persisted + sessionLines
    }

    // MARK: - Audit bridge

    func ingestAudit(
        message: String,
        category: CoordinationAuditLog.Category,
        level: CoordinationAuditLog.Level
    ) {
        let name = "audit.\(category.rawValue).\(level.rawValue)"
        trace(name, context: ["message": truncate(message, max: 240)])

        guard level == .error || level == .warn else { return }
        recordIssue(
            signature: signature(for: category, message: message),
            message: message,
            severity: level == .error ? .error : .warn,
            context: ["category": category.rawValue]
        )
    }

    // MARK: - Private

    private func signature(
        for category: CoordinationAuditLog.Category,
        message: String
    ) -> String {
        let lowered = message.lowercased()
        switch category {
        case .channel:
            if lowered.contains("history failed") { return "channel.history.failed" }
            if lowered.contains("not a member") { return "channel.join.denied" }
            if lowered.contains("opening") && lowered.contains("engineering") { return "channel.open.attempt" }
            return "channel.error"
        case .sse:
            if lowered.contains("disconnect") || lowered.contains("failed") { return "sse.disconnect" }
            return "sse.error"
        case .boot:
            if lowered.contains("failed") { return "boot.failed" }
            return "boot.warn"
        case .network:
            return "network.error"
        case .settings:
            return "settings.error"
        case .lifecycle:
            return "lifecycle.warn"
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { break }
                self.checkSpanTimeouts()
            }
        }
    }

    private func checkSpanTimeouts() {
        let now = Date()
        for (id, span) in activeSpans {
            let elapsed = now.timeIntervalSince(span.startedAt)
            guard elapsed >= span.timeoutSeconds else { continue }
            activeSpans.removeValue(forKey: id)
            var context = span.context
            context["duration_ms"] = String(Int(elapsed * 1000))
            context["timeout_s"] = String(Int(span.timeoutSeconds))
            trace("\(span.name).timeout", context: context)
            recordIssue(
                signature: "\(span.name).timeout",
                message: "\(span.name) exceeded \(Int(span.timeoutSeconds))s",
                severity: .error,
                context: context
            )
        }
    }

    private func sanitize(_ context: [String: String]) -> [String: String] {
        var cleaned: [String: String] = [:]
        for (key, value) in context {
            let lowered = key.lowercased()
            if lowered.contains("apikey") || lowered.contains("api_key") || lowered.contains("password") {
                continue
            }
            if lowered == "content" || lowered == "message_body" {
                continue
            }
            cleaned[key] = truncate(value, max: 280)
        }
        return cleaned
    }

    private func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    private struct Snapshot: Codable {
        var recentEvents: [TraceEvent]
        var pendingIssues: [PendingIssue]
    }

    private func persist() {
        let snapshot = Snapshot(recentEvents: recentEvents, pendingIssues: pendingIssues)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        recentEvents = snapshot.recentEvents
        pendingIssues = snapshot.pendingIssues
    }
}