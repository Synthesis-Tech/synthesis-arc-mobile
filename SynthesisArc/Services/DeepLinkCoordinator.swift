import Foundation

/// Bridges notification delegate (early init) to SwiftUI app state (late mount).
@MainActor
final class DeepLinkCoordinator: ObservableObject {
    static let shared = DeepLinkCoordinator()

    @Published private(set) var pendingRoute: DeepLinkRoute?
    @Published private(set) var publishEpoch: UInt = 0

    private init() {}

    func enqueue(_ route: DeepLinkRoute) {
        pendingRoute = route
        publishEpoch &+= 1
    }

    func consume() -> DeepLinkRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}