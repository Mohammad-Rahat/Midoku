import SwiftUI

enum ChapterGridStyle: String, SettingsValue, CaseIterable {
    case standard, compact, clean
    var title: String {
        switch self { case .standard: "Default"; case .compact: "Compact"; case .clean: "Clean" }
    }
}

enum MidokuAccent: String, SettingsValue, CaseIterable {
    case forest, slate, ochre, blue, purple, rose
    var title: String { rawValue.capitalized }
    var uiColor: UIColor {
        let choice = self
        return UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch choice {
            case .forest: return UIColor(red: dark ? 0.61 : 0.216, green: dark ? 0.78 : 0.416, blue: dark ? 0.67 : 0.314, alpha: 1)
            case .slate: return UIColor(red: dark ? 0.67 : 0.27, green: dark ? 0.77 : 0.38, blue: dark ? 0.86 : 0.47, alpha: 1)
            case .ochre: return UIColor(red: dark ? 0.88 : 0.49, green: dark ? 0.74 : 0.34, blue: dark ? 0.50 : 0.17, alpha: 1)
            case .blue: return .systemBlue
            case .purple: return .systemPurple
            case .rose: return .systemPink
            }
        }
    }
    @MainActor static func applyToWindows() {
        let color = AppSettings.appearance.accent.get().uiColor
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.tintColor = color }
        }
    }
}

private struct MidokuAccentModifier: ViewModifier {
    @AppStorage("Appearance.accent") private var accent = MidokuAccent.forest
    func body(content: Content) -> some View {
        content.tint(Color(uiColor: accent.uiColor)).accentColor(Color(uiColor: accent.uiColor))
    }
}

extension View {
    func midokuAccent() -> some View { modifier(MidokuAccentModifier()) }
}
