import SwiftUI

/// Detects iPhone landscape (compact height + compact width per orientation spec phase 4).
enum PhoneLandscapeLayout {
    static func isPhoneLandscape(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?
    ) -> Bool {
        #if os(iOS)
        horizontal == .compact && vertical == .compact
        #else
        false
        #endif
    }
}

/// Pins composer at bottom; thread scroll shrinks in iPhone landscape.
struct PinnedComposerThreadLayout<Thread: View, Composer: View>: View {
    let isPhoneLandscape: Bool
    @ViewBuilder let thread: () -> Thread
    @ViewBuilder let composer: () -> Composer

    var body: some View {
        if isPhoneLandscape {
            VStack(spacing: 0) {
                thread()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0)
                Divider()
                composer()
                    .layoutPriority(1)
            }
        } else {
            VStack(spacing: 0) {
                thread()
                composer()
            }
        }
    }
}