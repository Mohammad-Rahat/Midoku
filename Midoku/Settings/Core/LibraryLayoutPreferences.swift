import Foundation

nonisolated enum LibraryLayoutStyle: String, SettingChoice {
    case standard, compact, custom
    var title: String { rawValue.capitalized }
}

nonisolated struct LibraryLayoutPreferences: Codable, Equatable, Sendable {
    var style: LibraryLayoutStyle = .standard
    var portraitColumns = 3
    var landscapeColumns = 5

    func columns(landscape: Bool) -> Int {
        switch style {
        case .standard: landscape ? 4 : 2
        case .compact: landscape ? 6 : 3
        case .custom: landscape ? landscapeColumns : portraitColumns
        }
    }

    func validate() throws {
        guard (2...6).contains(portraitColumns), (2...10).contains(landscapeColumns) else {
            throw SettingsFailure.invalidBackup
        }
    }
}
