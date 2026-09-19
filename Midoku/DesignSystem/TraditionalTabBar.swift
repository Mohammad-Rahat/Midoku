import SwiftUI

struct AppTabBarHiddenPreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// A solid, edge-to-edge bar that does not adopt the system's floating glass style.
struct TraditionalTabBar: View {
    @Binding var selection: MidokuTab
    @Environment(AppSettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MidokuTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage).font(.system(size: 20, weight: .regular))
                        Text(tab.title).font(.caption2.weight(selection == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == tab ? settings.snapshot.preferences.accent.color : MidokuTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.top, 6).padding(.horizontal, 8)
        .background(MidokuTheme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(MidokuTheme.border).frame(height: 0.5) }
    }
}
