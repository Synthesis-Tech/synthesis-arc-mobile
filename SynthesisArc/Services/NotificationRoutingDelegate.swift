import Foundation
import UserNotifications

/// Routes notification taps into `CommandCenterState` deep links.
@MainActor
final class NotificationRoutingDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onRoute: ((DeepLinkRoute) -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let route = DeepLinkRoute(userInfo: userInfo)
        let payloadKeys = userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ", ")
        await deliver(route: route, payloadKeys: payloadKeys)
    }

    @MainActor
    private func deliver(route: DeepLinkRoute?, payloadKeys: String) {
        guard let route else {
            CoordinationAuditLog.shared.log(
                "Notification tap — unroutable payload (keys: \(payloadKeys.isEmpty ? "none" : payloadKeys))",
                category: .lifecycle,
                level: .warn
            )
            return
        }
        CoordinationAuditLog.shared.log(
            "Notification tap → \(route.auditLabel)",
            category: .lifecycle
        )
        onRoute?(route)
    }
}