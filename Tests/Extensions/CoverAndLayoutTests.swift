import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Independent covers and library layout")
struct CoverAndLayoutTests {
    @Test func entryAndChapterCoversStayIndependentAfterRefreshAndRestart() async throws {
        var snapshot = AppSnapshot()
        let source = SourceConnection(extensionID: "dev.midoku.test", name: "Test")
        snapshot.connections = [source]
        let details = MangaDetails(id: "book", title: "Book", description: "", coverURL: nil)
        let records = (1...3).map { ChapterRecord(id: "chapter-\($0)", title: "Chapter \($0)", number: String($0), ordinal: $0, language: "en") }
        let entryID = try snapshot.library.add(details: details, connectionID: source.id, records: records, language: "en")
        let entry = try #require(snapshot.library.entry(entryID))
        let slot = entry.slots[1]
        let variant = try #require(slot.preferred)
        let entryCover = LibraryCover(data: Data([0xFF, 0xD8, 0xFF, 0x01]))
        let chapterCover = LibraryCover(data: Data([0xFF, 0xD8, 0xFF, 0x02]))
        try snapshot.library.setCover(chapterCover, for: .chapter(entryID: entryID, slotID: slot.id, variantID: variant.id))
        #expect(snapshot.library.entry(entryID)?.coverID == nil)
        try snapshot.library.setCover(entryCover, for: .entry(entryID))
        try snapshot.library.refresh(details: details, connectionID: source.id, records: records, language: "en")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsPersistence(fileURL: root.appending(path: "library.sqlite"))
        try await store.save(snapshot, revision: 1)
        var restored = try #require(try await SettingsPersistence(fileURL: root.appending(path: "library.sqlite")).load())
        let saved = try #require(restored.library.entry(entryID))
        #expect(saved.coverID == entryCover.id)
        #expect(saved.slots[0].preferred?.edits.coverID == nil)
        #expect(saved.slots[1].preferred?.edits.coverID == chapterCover.id)
        #expect(saved.slots[2].preferred?.edits.coverID == nil)
        // Resetting a chapter to its first page must retain the entry cover.
        try restored.library.editEntry(entryID) { $0.slots[1].variants[0].edits.coverID = nil }
        #expect(restored.library.entry(entryID)?.coverID == entryCover.id)
        #expect(restored.library.entry(entryID)?.slots[1].preferred?.edits.coverID == nil)
        try restored.validate()
    }

    @Test func staleChapterCoverTargetDoesNotChangeAnyOwner() throws {
        var state = LibraryState()
        let entryID = try state.createManual(title: "Empty")
        let cover = LibraryCover(data: Data([0xFF, 0xD8, 0xFF]))
        #expect(throws: LibraryFailure.self) {
            try state.setCover(cover, for: .chapter(entryID: entryID, slotID: UUID(), variantID: UUID()))
        }
        #expect(state.covers.isEmpty)
        #expect(state.entry(entryID)?.coverID == nil)
        #expect(state.entry(entryID)?.sequenceRevision == 0)
    }

    @Test func oldPreferencesMigrateWithoutResettingUserSettings() throws {
        var old = AppPreferences()
        old.coverDensity = .compact; old.appearance = .dark; old.recordHistory = false
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "libraryLayout")
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.resolvedLibraryLayout.style == .compact)
        #expect(decoded.resolvedLibraryLayout.columns(landscape: false) == 3)
        #expect(decoded.appearance == .dark)
        #expect(!decoded.recordHistory)
    }

    @Test func customRowCountsRoundTripAndInvalidCountsAreRejected() throws {
        var state = AppSnapshot()
        state.preferences.libraryLayout = LibraryLayoutPreferences(style: .custom, portraitColumns: 4, landscapeColumns: 7)
        let (_, restored) = try BackupArchive.decode(BackupArchive(snapshot: state, extensions: [], appVersion: "test").encoded())
        #expect(restored.preferences.resolvedLibraryLayout.columns(landscape: false) == 4)
        #expect(restored.preferences.resolvedLibraryLayout.columns(landscape: true) == 7)
        state.preferences.libraryLayout?.portraitColumns = 0
        #expect(throws: SettingsFailure.self) { try state.validate() }
    }
}
