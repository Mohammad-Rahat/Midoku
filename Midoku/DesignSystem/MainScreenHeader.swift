import SwiftUI

struct MainScreenHeader<Actions: View>: ViewModifier {
    let title: String
    @ViewBuilder var actions: () -> Actions
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions().buttonStyle(.plain).labelStyle(.iconOnly)
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

/// An opaque navigation bar with ordinary back and action buttons.
struct SolidNavigationBar: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(MidokuTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(.plain)
                }.sharedBackgroundVisibility(.hidden)
            }
    }
}
