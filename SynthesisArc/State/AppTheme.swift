import SwiftUI

/// User-selectable appearance — System follows the device; Light/Dark override app-wide.
enum AppAppearance: String, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Settings section — segmented System / Light / Dark picker.
struct AppearancePickerSection: View {
    @Binding var selection: AppAppearance

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $selection) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.title, systemImage: appearance.systemImage)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            Text(appearanceCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceCaption: String {
        switch selection {
        case .system:
            return "Follows your device Light or Dark setting. Liquid Glass controls adapt automatically on iOS 26."
        case .light:
            return "Always use Light mode in this app."
        case .dark:
            return "Always use Dark mode in this app."
        }
    }
}

/// Applies stored appearance preference app-wide.
struct AppThemeModifier: ViewModifier {
    @ObservedObject private var config = AppConfig.shared

    func body(content: Content) -> some View {
        content.preferredColorScheme(config.appearance.colorScheme)
    }
}

extension View {
    func appTheme() -> some View {
        modifier(AppThemeModifier())
    }

    /// iOS 26 floating tab bar — call on `TabView` roots only.
    @ViewBuilder
    func phoneTabBarChrome() -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}