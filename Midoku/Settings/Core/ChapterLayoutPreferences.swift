import Foundation

nonisolated enum ChapterLayoutStyle: String, SettingChoice {
    case list, grid
    var title: String { rawValue.capitalized }
}

nonisolated struct ChapterLayoutPreferences: Codable, Equatable, Sendable {
    var style: ChapterLayoutStyle = .list
    var portraitColumns = 3
    var landscapeColumns = 5

    func columns(landscape: Bool) -> Int { landscape ? landscapeColumns : portraitColumns }

    func validate() throws {
        guard (2...6).contains(portraitColumns), (2...10).contains(landscapeColumns) else {
            throw SettingsFailure.invalidBackup
        }
    }
}
