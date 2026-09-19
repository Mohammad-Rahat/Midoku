import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Library add choices and Home preferences")
struct LibraryAddOptionsTests {
    @Test func addChoicesSurviveRestartAndInitialImportDoesNotCreateUpdates() async throws {
        var snapshot = AppSnapshot()
        let connection = SourceConnection(extensionID: "dev.midoku.tests", name: "Source")
        let category = LibraryCategory(name: "Favourites")
        snapshot.connections = [connection]; snapshot.categories = [category]
        let details = MangaDetails(id: "book", title: "Book", description: "", coverURL: nil)
        let chapters = (1...3).map { ChapterRecord(id: "c\($0)", title: "Chapter \($0)", number: String($0), ordinal: $0, language: "en") }
        let id = try snapshot.library.add(details: details, connectionID: connection.id, records: [chapters[0]],
            language: "en", categories: [category.id], complete: false, status: .reading, followsNewChapters: false)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "settings.sqlite")
        try await SettingsPersistence(fileURL: file).save(snapshot, revision: 1)
        var restored = try #require(try await SettingsPersistence(fileURL: file).load())
        let before = try #require(restored.library.entry(id))
        #expect(before.status == .reading && before.categoryIDs == [category.id])
        #expect(before.links.first?.followsNewChapters == false)
        #expect(before.links.first?.needsInitialImport == true)
        try restored.library.refresh(details: details, connectionID: connection.id, records: chapters, language: "en")
        #expect(restored.library.entry(id)?.slots.count == 3)
        #expect(restored.library.entry(id)?.links.first?.needsInitialImport == false)
        #expect(restored.library.updates.isEmpty)
        let later = ChapterRecord(id: "c4", title: "Later", number: "4", ordinal: 4, language: "en")
        try restored.library.refresh(details: details, connectionID: connection.id, records: chapters + [later], language: "en")
        #expect(restored.library.entry(id)?.slots.count == 3)
        #expect(restored.library.updates.isEmpty)
        try restored.validate()
    }

    @Test func laterUpdatesStillAppearAndDuplicateAddKeepsExistingChoices() throws {
        var snapshot = AppSnapshot()
        let connection = SourceConnection(extensionID: "dev.midoku.tests", name: "Source")
        let category = LibraryCategory(name: "Reading")
        snapshot.connections = [connection]; snapshot.categories = [category]
        let details = MangaDetails(id: "book", title: "Book", description: "", coverURL: nil)
        let chapter = ChapterRecord(id: "c1", title: "One", number: "1", ordinal: 1, language: nil)
        let id = try snapshot.library.add(details: details, connectionID: connection.id, records: [], language: nil,
            categories: [category.id], complete: false, status: .onHold)
        try snapshot.library.refresh(details: details, connectionID: connection.id, records: [chapter], language: nil)
        #expect(snapshot.library.updates.isEmpty)
        let next = ChapterRecord(id: "c2", title: "Two", number: "2", ordinal: 2, language: nil)
        try snapshot.library.refresh(details: details, connectionID: connection.id, records: [chapter, next], language: nil)
        #expect(snapshot.library.updates.count == 1)
        let duplicate = try snapshot.library.add(details: details, connectionID: connection.id, records: [chapter, next],
            language: nil, status: .completed, followsNewChapters: false)
        #expect(duplicate == id && snapshot.library.entries.count == 1)
        #expect(snapshot.library.entry(id)?.status == .onHold)
        #expect(snapshot.library.entry(id)?.categoryIDs == [category.id])
        #expect(snapshot.library.entry(id)?.links.first?.followsNewChapters == true)
    }

    @Test func initialImportKeepsExplicitlyRemovedChaptersExcluded() throws {
        var state = LibraryState()
        let connection = UUID()
        let details = MangaDetails(id: "book", title: "Book", description: "", coverURL: nil)
        let chapters = (1...2).map { ChapterRecord(id: "c\($0)", title: "Chapter \($0)", number: String($0), ordinal: $0, language: nil) }
        let id = try state.add(details: details, connectionID: connection, records: [chapters[0]], language: nil, complete: false)
        let slot = try #require(state.entry(id)?.slots.first)
        try state.removeSlots(entryID: id, slotIDs: [slot.id])
        try state.refresh(details: details, connectionID: connection, records: chapters, language: nil)
        #expect(state.entry(id)?.slots.count == 1)
        #expect(state.entry(id)?.slots.first?.preferred.flatMap { state.chapter($0.chapterID) }?.record.id == "c2")
        #expect(state.updates.isEmpty)
    }

    @Test func homeVisibilityAndAccentRoundTripWithoutClearingUpdates() throws {
        var snapshot = AppSnapshot()
        let connection = SourceConnection(extensionID: "dev.midoku.tests", name: "Source")
        snapshot.connections = [connection]
        let id = try snapshot.library.add(details: MangaDetails(id: "book", title: "Book", description: "", coverURL: nil),
            connectionID: connection.id, records: [ChapterRecord(id: "c1", title: "One", number: "1", ordinal: 1, language: nil)], language: nil)
        let chapter = try #require(snapshot.library.chapters.first)
        snapshot.library.updates = [LibraryUpdate(entryID: id, chapterID: chapter.id)]
        let before = snapshot.library.entries.map(\.id)
        snapshot.preferences.showHomeUpdates = false
        snapshot.preferences.accent = .ochre
        let (_, restored) = try BackupArchive.decode(BackupArchive(snapshot: snapshot, extensions: [], appVersion: "test").encoded())
        #expect(!restored.preferences.homeUpdatesVisible)
        #expect(restored.preferences.accent == .ochre)
        #expect(restored.library.entries.map(\.id) == before && restored.library.entry(id) != nil)
        #expect(restored.library.updates.map(\.id) == snapshot.library.updates.map(\.id))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.preferences)) as? [String: Any])
        object.removeValue(forKey: "showHomeUpdates")
        let old = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.homeUpdatesVisible)
        let oldLink = Data(#"{"id":"00000000-0000-4000-8000-000000000001","listingID":"00000000-0000-4000-8000-000000000002","followsNewChapters":true}"#.utf8)
        #expect(try JSONDecoder().decode(EntrySourceLink.self, from: oldLink).needsInitialImport == nil)
    }
}
