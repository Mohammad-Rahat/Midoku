import AidokuRunner
import Foundation
import Testing
@testable import Midoku

@MainActor
@Suite("Collection persistence and physical reader routing", .serialized)
struct CollectionIntegrationTests {
    @Test func pageLoadingAndPreloadingUsePhysicalChapterIdentity() async throws {
        await SourceManager.shared.waitForSourcesLoad()
        let sources = SourceStore.shared.sourcesByKey
        let disabled = SourceStore.shared.disabledSourceKeys
        defer { SourceStore.shared.update(sourcesByKey: sources, disabledSourceKeys: disabled) }
        var testSources = sources
        for key in ["mc.routing.a", "mc.routing.b"] {
            testSources[key] = AidokuRunner.Source(url: nil, key: key, name: key, version: 1,
                languages: ["en"], contentRating: .safe, runner: MCPageRoutingRunner())
        }
        SourceStore.shared.update(sourcesByKey: testSources, disabledSourceKeys: disabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MCCollectionStore(fileURL: root.appendingPathComponent("collection.json"))
        let a = AidokuRunner.Manga(sourceKey: "mc.routing.a", key: "book", title: "A")
        let b = AidokuRunner.Manga(sourceKey: "mc.routing.b", key: "book", title: "B")
        let entry = try store.add(a, chapters: [.init(key: "same", chapterNumber: 20), .init(key: "last", chapterNumber: 22)])
        store.copy(manga: b, chapters: [.init(key: "same", chapterNumber: 21)])
        try store.change { state in try state.library.paste(entryID: entry, revision: 0, choices: state.library.pastePreview(entryID: entry)) }
        let sequence = try MCReaderSequence(entryID: entry, slotID: try #require(store.library.entry(entry)?.slots.first).id, store: store)
        let model = ReaderPagedViewModel(source: testSources[a.sourceKey], manga: a)
        model.collectionSequence = sequence
        await model.loadPages(chapter: sequence.chapters[0])
        #expect(model.pages.first?.text == "mc.routing.a/book/same")
        await model.preload(chapter: sequence.chapters[1])
        #expect(model.preloadedPages.first?.sourceId == "mc.routing.b")
        await model.loadPages(chapter: sequence.chapters[1])
        #expect(model.pages.first?.text == "mc.routing.b/book/same")
        #expect(model.source?.key == "mc.routing.b")
        await model.loadPages(chapter: sequence.chapters[2])
        #expect(model.pages.first?.text == "mc.routing.a/book/last")
        await model.loadPages(chapter: sequence.chapters[1])
        #expect(model.pages.first?.text == "mc.routing.b/book/same")
        #expect(model.pages.first?.chapterId == sequence.chapters[1].key)
    }

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

private struct MCPageRoutingRunner: AidokuRunner.Runner {
    let features = AidokuRunner.SourceFeatures()
    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: [], hasNextPage: false)
    }
    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        [.init(content: .text("\(manga.sourceKey)/\(manga.key)/\(chapter.key)"))]
    }
}
