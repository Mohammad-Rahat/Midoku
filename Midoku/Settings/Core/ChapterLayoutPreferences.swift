import Foundation

nonisolated enum ChapterLayoutStyle: String, SettingChoice {
    case list, grid
    var title: String { rawValue.capitalized }
}

nonisolated enum ChapterGridStyle: String, SettingChoice {
    case standard, compact, thumbnail
    var title: String {
        switch self { case .standard: "Default"; case .compact: "Compact"; case .thumbnail: "Thumbnail" }
    }
}

nonisolated struct ChapterLayoutPreferences: Codable, Equatable, Sendable {
    var style: ChapterLayoutStyle = .list
    var portraitColumns = 3
    var landscapeColumns = 5
    // Optional for backups/settings written before grid presentation styles existed.
    var gridStyle: ChapterGridStyle? = nil
    var resolvedGridStyle: ChapterGridStyle { gridStyle ?? .standard }

    func columns(landscape: Bool) -> Int { landscape ? landscapeColumns : portraitColumns }

    func validate() throws {
        guard (2...6).contains(portraitColumns), (2...10).contains(landscapeColumns) else {
            throw SettingsFailure.invalidBackup
        }
    }
}
