import Foundation

/// Uploads automatic issue reports to forge-graphd blackboard for ops visibility.
@MainActor
final class FieldReportUploader {
    static let shared = FieldReportUploader()

    private var flushTask: Task<Void, Never>?
    private var isUploading = false

    private init() {}

    private static var autoIssueLoggingEnabled: Bool {
        if AppConfig.isConstructing { return false }
        return UserDefaults.standard.object(forKey: "tracing.autoIssueLogging") as? Bool ?? true
    }

    func scheduleFlush(delaySeconds: TimeInterval = 8) {
        guard Self.autoIssueLoggingEnabled else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flushPending()
        }
    }

    func flushPending() async {
        guard Self.autoIssueLoggingEnabled else { return }
        guard !E2EMode.isActive else { return }
        guard !isUploading else { return }

        let config = AppConfig.shared
        guard !config.apiKey.isEmpty else { return }

        let pending = UsabilityTrace.shared.pendingIssues.filter(\.isPendingUpload)
        guard !pending.isEmpty else { return }

        isUploading = true
        defer { isUploading = false }

        let client = config.makeClient()
        let agent = config.agentName
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for issue in pending.prefix(5) {
            var payload: [String: Any] = [
                "schema": "field-trace/v1",
                "id": issue.id.uuidString,
                "timestamp": formatter.string(from: issue.timestamp),
                "signature": issue.signature,
                "severity": issue.severity.rawValue,
                "message": issue.message,
                "context": issue.context,
                "device": UsabilityTrace.shared.deviceContext(),
                "app": UsabilityTrace.shared.appContext(),
                "graphd": "\(config.graphdHost):\(config.graphdPort)",
                "agent": agent,
                "audit_tail": UsabilityTrace.shared.auditTail(limit: 30),
                "recent_events": UsabilityTrace.shared.recentEvents.prefix(15).map {
                    [
                        "name": $0.name,
                        "ts": formatter.string(from: $0.timestamp),
                        "context": $0.context
                    ]
                }
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: jsonData, encoding: .utf8) else { continue }

            let key = "ops/field-trace/\(agent)/\(issue.signature)/\(issue.id.uuidString.prefix(8))"
            do {
                try await client.setBlackboard(key: key, value: json, ttlSeconds: 7 * 86_400)
                UsabilityTrace.shared.markIssueUploaded(issue.id)
                UsabilityTrace.shared.noteUploadResult(at: Date(), error: nil)
                CoordinationAuditLog.shared.log(
                    "Issue report uploaded — \(issue.signature)",
                    category: .network
                )
            } catch {
                UsabilityTrace.shared.noteUploadResult(at: Date(), error: error.localizedDescription)
                CoordinationAuditLog.shared.log(
                    "Issue report upload failed — \(issue.signature): \(error.localizedDescription)",
                    category: .network,
                    level: .warn
                )
                break
            }
        }
    }
}