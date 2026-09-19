import AidokuRunner
import Foundation

extension MCCollectionStore {
    func adoptExistingLibrary() async {
        await SourceManager.shared.waitForSourcesLoad()
        let values = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(context: context).compactMap { item -> AidokuRunner.Manga? in
                guard let manga = item.manga else { return nil }
                var value = manga.toNewManga()
                value.chapters = CoreDataManager.shared.getChapters(mangaId: value.identifier, context: context).map { $0.toChapter().toNew() }
                return value
            }
        }
        for manga in values where !snapshot.adopted.contains(manga.identifier) {
            do { _ = try add(manga, chapters: manga.chapters ?? []) }
            catch { self.error = error.localizedDescription }
        }
    }

    func removePrimaryEntry(for mangaId: MangaIdentifier) {
        guard let connection = snapshot.connections.first(where: { $0.sourceKey == mangaId.sourceKey }),
              let listing = library.listings.first(where: { $0.identity.connectionID == connection.id && $0.identity.externalID == mangaId.mangaKey }) else { return }
        let ids = Set(library.entries.filter { $0.primaryListingID == listing.id }.map(\.id))
        if !ids.isEmpty { perform { $0.library.removeEntries(ids) } }
    }
}
