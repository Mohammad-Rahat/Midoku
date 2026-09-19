import SwiftUI

/// Controls overlay one stable, full-screen page viewport in both reading modes.
struct ReaderChrome<Pages: View, Controls: View>: View {
    let title: String
    let subtitle: String
    let visible: Bool
    let preferences: () -> Void
    @ViewBuilder var pages: (CGSize) -> Pages
    @ViewBuilder var controls: () -> Controls
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GeometryReader { safeArea in
        GeometryReader { geometry in
            pages(geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .top) {
                    HStack(spacing: 12) {
                        Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Back")
                        VStack(spacing: 4) {
                            Text(title).font(.headline).lineLimit(1)
                            Text(subtitle).font(.caption).foregroundStyle(MidokuTheme.secondaryText).lineLimit(1)
                        }.frame(maxWidth: .infinity)
                        Button(action: preferences) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Reader preferences")
                    }
                    .buttonStyle(.plain).padding(.horizontal, 8).padding(.bottom, 6)
                    .padding(.top, safeArea.safeAreaInsets.top)
                    .background(MidokuTheme.surface)
                    .opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
                }
                .overlay(alignment: .bottom) {
                    controls().padding(.bottom, safeArea.safeAreaInsets.bottom)
                        .background(MidokuTheme.surface)
                        .opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
                }
        }
        .ignoresSafeArea(.container)
        }
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(!visible)
        .modifier(ReaderBackGesture())
        .preference(key: ReaderControlsPreference.self, value: visible)
    }
}

struct ReaderPageControls: View {
    let index: Int
    let count: Int
    let jump: (Int) -> Void
    @Environment(\.readerChapterNavigation) private var navigation
    var body: some View {
        HStack(spacing: 0) {
            Button { navigation.previous?() } label: { Image(systemName: "backward.end") }
                .disabled(navigation.previous == nil).accessibilityLabel("Previous chapter")
            Button { jump(index - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0).accessibilityLabel("Previous page")
            Spacer(minLength: 0)
            Menu {
                Picker("Page", selection: Binding(get: { index }, set: jump)) {
                    ForEach(0..<count, id: \.self) { Text("Page \($0 + 1)").tag($0) }
                }
            } label: { Text("\(count == 0 ? 0 : index + 1) / \(count)").monospacedDigit().font(.subheadline) }
                .accessibilityLabel("Page \(index + 1) of \(count). Choose page")
            Spacer(minLength: 0)
            Button { jump(index + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(index + 1 >= count).accessibilityLabel("Next page")
            Button { navigation.next?() } label: { Image(systemName: "forward.end") }
                .disabled(navigation.next == nil).accessibilityLabel("Next chapter")
        }
        .buttonStyle(ReaderControlButtonStyle())
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}
private struct ReaderControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
    }
}
