import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Chapter layout persistence")
struct ChapterLayoutTests {
    @Test func existingSettingsKeepListAndMangaCounts() throws {
        var settings = AppSnapshot()
        settings.preferences.libraryLayout = LibraryLayoutPreferences(style: .custom, portraitColumns: 4, landscapeColumns: 7)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        var preferences = try #require(object["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "chapterLayout")
        object["preferences"] = preferences
        let restored = try JSONDecoder().decode(AppSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try restored.validate()
        #expect(restored.preferences.resolvedChapterLayout.style == .list)
        #expect(restored.preferences.resolvedLibraryLayout.columns(landscape: false) == 4)
        #expect(restored.preferences.resolvedLibraryLayout.columns(landscape: true) == 7)
    }

    @Test func chapterGridSurvivesRestartIndependentlyOfMangaLayout() async throws {
        var settings = AppSnapshot()
        settings.preferences.libraryLayout = LibraryLayoutPreferences(style: .custom, portraitColumns: 4, landscapeColumns: 7)
        settings.preferences.chapterLayout = ChapterLayoutPreferences(style: .grid, portraitColumns: 2, landscapeColumns: 5)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "settings.sqlite")
        try await SettingsPersistence(fileURL: url).save(settings, revision: 1)
        let restored = try #require(try await SettingsPersistence(fileURL: url).load())
        #expect(restored.preferences.resolvedChapterLayout.style == .grid)
        #expect(restored.preferences.resolvedChapterLayout.columns(landscape: false) == 2)
        #expect(restored.preferences.resolvedChapterLayout.columns(landscape: true) == 5)
        #expect(restored.preferences.resolvedLibraryLayout.columns(landscape: false) == 4)
        try restored.validate()
    }

    @Test func backupRejectsInvalidChapterGridCounts() {
        for value in [0, 1, 7, Int.max] {
            var settings = AppSnapshot()
            settings.preferences.chapterLayout = ChapterLayoutPreferences(style: .grid, portraitColumns: value, landscapeColumns: 5)
            #expect(throws: SettingsFailure.invalidBackup) { try settings.validate() }
        }
        var settings = AppSnapshot()
        settings.preferences.chapterLayout = ChapterLayoutPreferences(style: .grid, portraitColumns: 3, landscapeColumns: 11)
        #expect(throws: SettingsFailure.invalidBackup) { try settings.validate() }
    }
}
