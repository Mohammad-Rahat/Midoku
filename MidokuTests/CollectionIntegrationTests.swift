import AidokuRunner
import Foundation
import Testing
@testable import Midoku

@MainActor
@Suite("Collection persistence and physical reader routing")
struct CollectionIntegrationTests {
    @Test func readerRoutesIdenticalChapterKeysToTheirOwnSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        let a = AidokuRunner.Manga(sourceKey: "source-a", key: "same-manga", title: "Original A")
        let b = AidokuRunner.Manga(sourceKey: "source-b", key: "same-manga", title: "Original B")
        let entry = try store.add(a, chapters: [.init(key: "same-chapter", chapterNumber: 20), .init(key: "22", chapterNumber: 22)])
        store.copy(manga: b, chapters: [.init(key: "same-chapter", chapterNumber: 21)])
        try store.change { state in try state.library.paste(entryID: entry, revision: 0, choices: state.library.pastePreview(entryID: entry)) }
        let reloaded = MCCollectionStore(fileURL: file)
        let personal = try #require(reloaded.library.entry(entry))
        let sequence = try MCReaderSequence(entryID: entry, slotID: try #require(personal.slots.first).id, store: reloaded)
        #expect(sequence.routes.map { $0.identifier.sourceKey } == ["source-a", "source-b", "source-a"])
        #expect(Set(sequence.chapters.map(\.key)).count == 3)
        #expect(sequence.routes[0].chapter.key == sequence.routes[1].chapter.key)
        let next = try #require(sequence.adjacent(to: sequence.chapters[0], offset: 1))
        #expect(sequence.route(next)?.identifier.sourceKey == "source-b")
        #expect(sequence.route(next)?.identifier.chapterKey == "same-chapter")
        #expect(reloaded.library.clipboard.count == 1)
        try reloaded.snapshot.validate()
    }

    @Test func failedPersistenceDoesNotPublishChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("collection.json")
        let store = MCCollectionStore(fileURL: file)
        try store.change { _ = try $0.library.createManual(title: "Keep me") }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try store.change { _ = try $0.library.createManual(title: "Do not publish") } }
        #expect(store.library.entries.count == 1)
    }

    @Test func invalidRestoreDoesNotReplaceCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        try store.change { _ = try $0.library.createManual(title: "Keep me") }
        let before = try store.backupData()
        var corrupt = store.snapshot; corrupt.version = 999
        #expect(throws: (any Error).self) { try store.restore(JSONEncoder().encode(corrupt)) }
        #expect(store.library.entries.count == 1)
        try store.restore(before)
        #expect(store.library.title(try #require(store.library.entries.first)) == "Keep me")
    }
}
