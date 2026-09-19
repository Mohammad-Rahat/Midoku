import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Cache, quick add, and reset details")
struct CacheAndResetTests {
    @Test func coversSurviveRestartAndClearOnlyCacheDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Covers")
        let cache = ImageDiskCache(directory: folder)
        let cover = Data([1, 2, 3, 4])
        try cache.store(cover, key: "source-a\ncover")
        let recreated = ImageDiskCache(directory: folder)
        #expect(recreated.read("source-a\ncover") == cover)
        #expect(recreated.read("source-b\ncover") == nil)
        let saved = root.appending(path: "saved-download")
        try cover.write(to: saved)
        try recreated.clear()
        #expect(cache.read("source-a\ncover") == nil)
        #expect(try Data(contentsOf: saved) == cover)
    }
    @Test func diskCacheEnforcesBudgetAndExpiry() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ImageDiskCache(directory: folder, maximumBytes: 6, lifetime: 60)
        try cache.store(Data([1, 2, 3, 4]), key: "old")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30)], ofItemAtPath: cache.file(for: "old").path)
        try cache.store(Data([5, 6, 7, 8]), key: "new")
        #expect(cache.read("old") == nil)
        #expect(cache.read("new") != nil)
        #expect(cache.read("new", now: Date(timeIntervalSinceNow: 61)) == nil)
    }
    @Test func quickAddIsDurableBeforeCompleteChapterFetchAndRefreshFillsIt() async throws {
        var state = AppSnapshot()
        let source = SourceConnection(extensionID: "dev.midoku.test", name: "Test")
        state.connections = [source]
        let details = MangaDetails(id: "book", title: "Book", description: "", coverURL: nil)
        let records = (1...3).map { ChapterRecord(id: "c\($0)", title: "Chapter \($0)", number: String($0), ordinal: $0, language: "en") }
        // An earlier Browse/copy operation may have remembered the full list.
        _ = try state.library.remember(details: details, connectionID: source.id, records: records, complete: true)
        let id = try state.library.add(details: details, connectionID: source.id, records: [records[0]], language: "en", complete: false)
        #expect(state.library.chapters.allSatisfy(\.available))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsPersistence(fileURL: root.appending(path: "library.sqlite"))
        try await store.save(state, revision: 1)
        var restored = try #require(try await SettingsPersistence(fileURL: root.appending(path: "library.sqlite")).load())
        #expect(restored.library.entry(id)?.slots.count == 1)
        try restored.library.refresh(details: details, connectionID: source.id, records: records, language: "en")
        #expect(restored.library.entry(id)?.slots.count == 3)
        #expect(try restored.library.add(details: details, connectionID: source.id, records: records, language: "en") == id)
        #expect(restored.library.entries.count == 1)
        try restored.validate()
    }
    @Test func resetKeepsMixedSourcesProgressAndCompositionAfterRestart() async throws {
        var state = AppSnapshot()
        let a = SourceConnection(extensionID: "dev.midoku.a", name: "A")
        let b = SourceConnection(extensionID: "dev.midoku.b", name: "B")
        state.connections = [a, b]
        let category = LibraryCategory(name: "Reading"); state.categories = [category]
        let details = MangaDetails(id: "book-a", title: "Original", description: "Source details", coverURL: nil)
        let record = ChapterRecord(id: "a1", title: "First", number: "1", ordinal: 1, language: "en")
        let id = try state.library.add(details: details, connectionID: a.id, records: [record], language: "en", categories: [category.id])
        _ = try state.library.remember(details: MangaDetails(id: "book-b", title: "Other", description: "", coverURL: nil), connectionID: b.id,
            records: [ChapterRecord(id: "b2", title: "Second", number: "2", ordinal: 2, language: "en")], complete: true)
        let extra = try #require(state.library.chapters.last)
        try state.library.copy([CopiedChapter(chapterID: extra.id)])
        try state.library.paste(entryID: id, revision: 0, choices: state.library.pastePreview(entryID: id))
        let before = try #require(state.library.entry(id))
        state.progress = [ReadingPosition(identity: extra.identity, pageID: "p", pageIndex: 2, pageCount: 10, fraction: 0.2, updatedAt: .now)]
        state.library.completed.insert(extra.identity)
        try state.library.editEntry(id) {
            $0.titleOverride = "Custom"; $0.descriptionOverride = "Custom"; $0.authorOverride = "Me"; $0.hidesCover = true
            $0.readerOverride = ReaderPreferences(); $0.manualOrder = true; $0.descendingDisplay = true
            $0.slots[1].variants[0].edits = ChapterEdits(title: "Renamed", number: "99", volume: "9")
            $0.slots.reverse()
        }
        try state.library.resetDetails(id)
        let reset = try #require(state.library.entry(id))
        #expect(state.library.title(reset) == "Original")
        #expect(reset.slots.map(\.id) == before.slots.map(\.id))
        #expect(reset.links.map(\.id) == before.links.map(\.id))
        #expect(reset.slots[1].preferred?.chapterID == extra.id)
        #expect(reset.slots.allSatisfy { $0.variants.allSatisfy { $0.edits.title == nil && $0.edits.number == nil && $0.edits.coverID == nil } })
        #expect(reset.categoryIDs == [category.id])
        #expect(reset.readerOverride == nil && !reset.manualOrder && !reset.hidesCover && !reset.descendingDisplay)
        #expect(state.progress.first?.pageIndex == 2)
        #expect(state.library.completed.contains(extra.identity))
        let (_, restored) = try BackupArchive.decode(BackupArchive(snapshot: state, extensions: [], appVersion: "test").encoded())
        #expect(restored.library.entry(id)?.slots.count == 2)
        #expect(restored.progress.first?.id == extra.identity)
        try restored.validate()
    }
    @Test func oldHistoryDecodesWithoutCoverField() throws {
        let connection = UUID()
        let record = ReadingRecord(identity: SourceChapterIdentity(listing: SourceListingIdentity(connectionID: connection, externalID: "book"), externalID: "chapter"), mangaTitle: "Book", sourceName: "Source", chapter: ChapterRecord(id: "chapter", title: "One", number: nil, ordinal: 1, language: nil), openedAt: .now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "coverURL")
        let decoded = try JSONDecoder().decode(ReadingRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.coverURL == nil)
        #expect(decoded.identity == record.identity)
    }
}
