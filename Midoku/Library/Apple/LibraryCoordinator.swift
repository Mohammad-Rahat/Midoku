import Foundation
import Observation

@MainActor
@Observable
final class LibraryCoordinator {
    let settings: AppSettingsStore
    let extensions: ExtensionEnvironment
    private(set) var refreshing = false
    private(set) var refreshMessage: String?
    init(settings: AppSettingsStore, extensions: ExtensionEnvironment) { self.settings = settings; self.extensions = extensions }

    func fullSnapshot(adapter: any SourceAdapter, mangaID: String, language: String?) async throws -> (MangaDetails, [ChapterRecord]) {
        let details = try await adapter.details(mangaID: mangaID)
        guard adapter.manifest.capabilities.contains(.chapters) else { return (details, []) }
        var cursor: String?, seen = Set<String>(), chapters: [ChapterRecord] = [], ids = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await adapter.chapters(mangaID: mangaID, cursor: cursor, language: language)
            for item in page.items where ids.insert(item.id).inserted { chapters.append(item) }
            guard chapters.count <= 50_000 else { throw LibraryFailure.incomplete }
            cursor = page.nextCursor
            if let cursor {
                guard seen.insert(cursor).inserted, seen.count <= 1000 else { throw LibraryFailure.incomplete }
            }
        } while cursor != nil
        return (details, chapters)
    }

    func add(adapter: any SourceAdapter, mangaID: String, language: String?, categories: Set<UUID>) async throws -> UUID {
        let result = try await fullSnapshot(adapter: adapter, mangaID: mangaID, language: language)
        try Task.checkCancellation()
        var id: UUID?
        try await settings.commit { state in
            id = try state.library.add(details: result.0, connectionID: adapter.connection.id, records: result.1, language: language, categories: categories)
        }
        guard let id else { throw LibraryFailure.missing }
        return id
    }

    /// Save the already-visible listing immediately. A full refresh fills remaining chapters;
    /// partial pages must never mark previously remembered releases as unavailable.
    func addVisible(details: MangaDetails, connection: SourceConnection, records: [ChapterRecord], language: String?) async throws -> UUID {
        var entryID: UUID?
        try await settings.commit { state in
            entryID = try state.library.add(details: details, connectionID: connection.id, records: records,
                language: language, complete: false)
        }
        guard let entryID else { throw LibraryFailure.missing }
        return entryID
    }

    func copy(details: MangaDetails, connection: SourceConnection, chapters: [ChapterRecord]) async throws {
        try await settings.commit { state in
            _ = try state.library.remember(details: details, connectionID: connection.id, records: chapters, complete: false)
            let listing = SourceListingIdentity(connectionID: connection.id, externalID: details.id)
            let items = chapters.compactMap { record in state.library.chapters.first { $0.identity == SourceChapterIdentity(listing: listing, externalID: record.id) }.map { CopiedChapter(chapterID: $0.id) } }
            try state.library.copy(items)
        }
    }

    func refresh(entryIDs: Set<UUID>? = nil, automatic: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true; refreshMessage = nil
        defer { refreshing = false }
        let generation = settings.restoreGeneration
        struct Query: Hashable { let listingID: UUID; let language: String? }
        let entries = settings.snapshot.library.entries.filter { entryIDs == nil || entryIDs?.contains($0.id) == true }
        var queries: [Query] = [], seen = Set<Query>()
        for entry in entries {
            for link in entry.links {
                let query = Query(listingID: link.listingID, language: link.language)
                if seen.insert(query).inserted { queries.append(query) }
            }
        }
        var failed = 0
        for query in queries {
            guard !Task.isCancelled, generation == settings.restoreGeneration else { return }
            guard let listing = settings.snapshot.library.listing(query.listingID) else { continue }
            if automatic, let date = listing.refreshedAt, Date().timeIntervalSince(date) < 900 { continue }
            do {
                guard let connection = extensions.connections.first(where: { $0.id == listing.identity.connectionID }) else { throw LibraryFailure.missing }
                let adapter = try await extensions.adapter(for: connection, interaction: automatic ? .background : .foreground)
                let result = try await fullSnapshot(adapter: adapter, mangaID: listing.identity.externalID, language: query.language)
                try Task.checkCancellation()
                guard generation == settings.restoreGeneration else { return }
                try await settings.commit { state in try state.library.refresh(details: result.0, connectionID: connection.id, records: result.1, language: query.language) }
            } catch {
                if Task.isCancelled { return }
                failed += 1
                settings.update { state in
                    if let index = state.library.listings.firstIndex(where: { $0.id == query.listingID }) {
                        state.library.listings[index].lastError = error.localizedDescription
                    }
                }
            }
        }
        refreshMessage = failed == 0 ? nil : "\(failed) source refresh\(failed == 1 ? "" : "es") need attention. Your saved chapters are kept."
    }
}
