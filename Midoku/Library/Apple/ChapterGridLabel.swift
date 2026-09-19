import SwiftUI

/// Shared by library and source chapters: at most three single-line text rows.
struct ChapterGridLabel<Cover: View>: View {
    @Environment(\.midokuAccentFill) private var accentFill
    let title: String
    let subtitle: String?
    let detail: String?
    let style: ChapterGridStyle
    let showsCover: Bool
    let selected: Bool?
    @ViewBuilder var cover: () -> Cover

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsCover || style != .standard {
                cover().aspectRatio(2.0 / 3, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        if style == .compact {
                            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                                .foregroundStyle(.white).padding(.horizontal, 8).padding(.top, 24).padding(.bottom, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) { selection }
            } else { selection }
            if style == .standard {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).lineLimit(1).truncationMode(.tail) }
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(MidokuTheme.secondaryText).lineLimit(1).truncationMode(.tail)
                }
            }
        }.foregroundStyle(MidokuTheme.primaryText).contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, subtitle, detail].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(selected == true ? .isSelected : [])
    }
    @ViewBuilder private var selection: some View {
        if let selected {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(.white, accentFill).padding(4)
        }
    }
}
