import AidokuRunner
import SwiftUI

/// A reader session freezes the personal order. Display keys are local variant UUIDs;
/// network, download and history operations always resolve the physical source tuple.
@MainActor
final class MCReaderSequence {
    struct Route {
        let identity: MCSourceChapterIdentity
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
        let displayChapter: AidokuRunner.Chapter
        var identifier: ChapterIdentifier {
            .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        }
        var source: AidokuRunner.Source? { SourceStore.shared.source(for: manga.sourceKey) }
    }
    let entryID: UUID
    let title: String
    let routes: [Route]
    let initialKey: String
    var chapters: [AidokuRunner.Chapter] { routes.map(\.displayChapter) }

    init(entryID: UUID, slotID: UUID, store: MCCollectionStore = .shared) throws {
        guard let entry = store.library.entry(entryID) else { throw MCLibraryFailure.missing }
        self.entryID = entryID
        title = store.library.title(entry)
        var routes: [Route] = []
        var initial: String?
        for slot in entry.slots {
            guard let variant = slot.preferred, let libraryChapter = store.library.chapter(variant.chapterID),
                  let record = store.physical(libraryChapter.identity) else { throw MCLibraryFailure.missing }
            let original = record.chapter
            let display = AidokuRunner.Chapter(key: variant.id.uuidString,
                title: variant.edits.title ?? original.title,
                chapterNumber: variant.edits.number.flatMap(Float.init) ?? original.chapterNumber,
                volumeNumber: variant.edits.volume.flatMap(Float.init) ?? original.volumeNumber,
                dateUploaded: original.dateUploaded, scanlators: original.scanlators,
                url: original.url, language: original.language, thumbnail: original.thumbnail, locked: original.locked)
            routes.append(Route(identity: libraryChapter.identity, manga: record.manga, chapter: original, displayChapter: display))
            if slot.id == slotID { initial = display.key }
        }
        guard let initial else { throw MCLibraryFailure.missing }
        self.routes = routes
        initialKey = initial
    }

    func route(_ chapter: AidokuRunner.Chapter) -> Route? { routes.first { $0.displayChapter.key == chapter.key } }
    func route(key: String) -> Route? { routes.first { $0.displayChapter.key == key } }
    func adjacent(to chapter: AidokuRunner.Chapter, offset: Int) -> AidokuRunner.Chapter? {
        guard let index = routes.firstIndex(where: { $0.displayChapter.key == chapter.key }), routes.indices.contains(index + offset) else { return nil }
        return routes[index + offset].displayChapter
    }
}

struct MCReaderSheet: Identifiable {
    let id = UUID()
    let sequence: MCReaderSequence
}

struct MCReaderView: UIViewControllerRepresentable {
    let sequence: MCReaderSequence
    func makeUIViewController(context: Context) -> ReaderNavigationController {
        guard let route = sequence.route(key: sequence.initialKey) else { preconditionFailure("Validated reader route missing") }
        let reader = ReaderViewController(source: route.source, manga: route.manga, chapter: route.displayChapter, collectionSequence: sequence)
        return ReaderNavigationController(readerViewController: reader)
    }
    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {}
}
