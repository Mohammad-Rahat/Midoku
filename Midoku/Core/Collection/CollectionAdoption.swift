import AidokuRunner
import Foundation

extension MCCollectionStore {
    func adoptExistingLibrary() async {
        await SourceManager.shared.waitForSourcesLoad()
        await importLegacyCategories()
        let values = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(context: context).compactMap { item -> (AidokuRunner.Manga, [String])? in
                guard let manga = item.manga else { return nil }
                var value = manga.toNewManga()
                value.chapters = CoreDataManager.shared.getChapters(mangaId: value.identifier, context: context).map { $0.toChapter().toNew() }
                let categories = CoreDataManager.shared.getCategories(mangaId: value.identifier, context: context).filter { !$0.group }.compactMap(\.title)
                return (value, categories)
            }
        }
        for (manga, categories) in values where !snapshot.adopted.contains(manga.identifier) {
            do { _ = try add(manga, chapters: manga.chapters ?? [], categories: Set(snapshot.categories.filter { categories.contains($0.name) }.map(\.id))) }
            catch { self.error = error.localizedDescription }
        }
    }

    func importLegacyCategories() async {
        guard snapshot.legacyCategoriesImported != true else { return }
        let (names, assignments) = await CoreDataManager.shared.container.performBackgroundTask { context in
            let names = CoreDataManager.shared.getCategoryTitles(context: context)
            var assignments: [MangaIdentifier: [String]] = [:]
            for item in CoreDataManager.shared.getLibraryManga(context: context) {
                guard let manga = item.manga else { continue }
                let id = manga.toNewManga().identifier
                assignments[id] = CoreDataManager.shared.getCategories(mangaId: id, context: context).filter { !$0.group }.compactMap(\.title)
            }
            return (names, assignments)
        }
        guard snapshot.legacyCategoriesImported != true else { return }
        perform { state in
            for name in names where !state.categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                state.categories.append(MCCategory(name: name))
            }
            for index in state.library.entries.indices {
                guard let listing = state.library.entries[index].primaryListingID,
                      let manga = state.manga.first(where: { $0.listingID == listing })?.manga,
                      let names = assignments[manga.identifier] else { continue }
                let ids = state.categories.filter { category in names.contains { $0.localizedCaseInsensitiveCompare(category.name) == .orderedSame } }.map(\.id)
                state.library.entries[index].categoryIDs.formUnion(ids)
            }
            state.legacyCategoriesImported = true
        }
    }

    func removePrimaryEntry(for mangaId: MangaIdentifier) {
        guard let connection = snapshot.connections.first(where: { $0.sourceKey == mangaId.sourceKey }),
              let listing = library.listings.first(where: { $0.identity.connectionID == connection.id && $0.identity.externalID == mangaId.mangaKey }) else { return }
        let ids = Set(library.entries.filter { $0.primaryListingID == listing.id }.map(\.id))
        if !ids.isEmpty { perform { $0.library.removeEntries(ids) } }
    }
}
