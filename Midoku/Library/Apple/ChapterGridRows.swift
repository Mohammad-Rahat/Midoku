import SwiftUI

/// One native List row per grid row keeps long chapter collections virtualized.
struct ChapterGridRows<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    @ViewBuilder var cell: (Item) -> Cell

    var body: some View {
        ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<columns, id: \.self) { offset in
                    if start + offset < items.count {
                        cell(items[start + offset]).frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Color.clear.frame(minWidth: 0, maxWidth: .infinity, minHeight: 1)
                    }
                }
            }.listRowSeparator(.hidden)
        }
    }
}
