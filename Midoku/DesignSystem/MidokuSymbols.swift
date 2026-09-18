import SwiftUI

// SF Symbols are resolved by iOS. No Apple font or symbol files are bundled.
enum MidokuTab: String, CaseIterable, Identifiable {
    case home, library, browse, history, settings
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .browse: "Browse"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .browse: "safari"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

enum MidokuSymbol {
    static let search = "magnifyingglass"
    static let filter = "line.3.horizontal.decrease"
    static let pin = "pin"
    static let unpin = "pin.slash"
    static let add = "plus"
    static let edit = "pencil"
    static let copy = "doc.on.doc"
    static let paste = "doc.on.clipboard"
    static let remove = "trash"
    static let download = "arrow.down.circle"
    static let downloaded = "checkmark.circle"
    static let source = "square.grid.2x2"
    static let categories = "folder"
    static let reorder = "line.3.horizontal"
    static let lock = "lock"
    static let more = "ellipsis"
    static let close = "xmark"
    static let retry = "arrow.clockwise"
}
