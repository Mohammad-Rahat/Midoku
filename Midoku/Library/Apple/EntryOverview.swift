import SwiftUI

/// Compact cover, typeset title and reading controls shared by both entry screens.
struct EntryOverview<Cover: View, Action: View>: View {
    let title: String
    let author: String?
    let metadata: String
    let detail: String?
    @ViewBuilder var cover: () -> Cover
    @ViewBuilder var action: () -> Action
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            cover().frame(width: 100, height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).accessibilityAddTraits(.isHeader)
                if let author, !author.isEmpty {
                    Text(author).font(.subheadline).foregroundStyle(MidokuTheme.secondaryText).lineLimit(2)
                }
                if !metadata.isEmpty { Text(metadata).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                if let detail, !detail.isEmpty { Text(detail).font(.caption.weight(.semibold)).foregroundStyle(.tint) }
                action().font(.subheadline.weight(.semibold)).buttonStyle(.borderedProminent).controlSize(.small)
                    .padding(.top, 2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EntrySynopsis: View {
    let text: String
    @State private var expanded = false
    @State private var attributed = AttributedString()

    var body: some View {
        if !text.isEmpty {
            Button { expanded.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(attributed).font(.subheadline).lineLimit(expanded ? nil : 2)
                        .foregroundStyle(MidokuTheme.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                        .foregroundStyle(.tint).padding(.top, 4)
                }.frame(minHeight: 44, alignment: .top).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse description" : "Read description")
                .accessibilityValue(Text(attributed))
                .task(id: text) {
                    attributed = (try? AttributedString(markdown: text,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
                }
        }
    }
}

struct EntryListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain).listSectionSpacing(8)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .scrollContentBackground(.hidden).background(MidokuTheme.background)
            .foregroundStyle(MidokuTheme.primaryText)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationBarTitleDisplayMode(.inline).modifier(NativeNavigationBar())
    }
}
