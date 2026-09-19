import SwiftUI

struct MainScreenHeader<Actions: View>: ViewModifier {
    let title: String
    @ViewBuilder var actions: () -> Actions
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions().buttonStyle(MidokuIconButtonStyle()).labelStyle(.iconOnly)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
            .background(MidokuTheme.background)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MidokuTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
extension View {
    func mainScreenHeader<Actions: View>(_ title: String, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(MainScreenHeader(title: title, actions: actions))
    }
    func mainScreenHeader(_ title: String) -> some View {
        mainScreenHeader(title) { EmptyView() }
    }
}

/// Keep the native back button so navigation retains iOS interactive swipe-back.
struct NativeNavigationBar: ViewModifier {
    @Environment(AppSettingsStore.self) private var settings
    func body(content: Content) -> some View {
        content
            .tint(settings.snapshot.preferences.accent.color)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(MidokuTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct MidokuIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(.tint)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct GridLandscapeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var gridLandscape: Bool {
        get { self[GridLandscapeKey.self] }
        set { self[GridLandscapeKey.self] = newValue }
    }
}
