#if DEBUG
import Foundation

/// Opt-in simulator screenshots use a separate store; production builds contain no seeded library.
@MainActor
enum LibraryPreviewData {
    static func prepare(_ settings: AppSettingsStore) async throws -> UUID {
        if let existing = settings.snapshot.library.entries.first { return existing.id }
        var firstID: UUID?
        try await settings.commit { state in
            state.preferences.refreshOnLaunch = false
            let a = SourceConnection(extensionID: "dev.midoku.fixture-a", name: "Source A", isEnabled: false)
            let b = SourceConnection(extensionID: "dev.midoku.fixture-b", name: "Source B", isEnabled: false)
            state.connections += [a, b]
            let category = LibraryCategory(name: "Reading"); state.categories.append(category)
            let details = MangaDetails(id: "preview-a", title: "The quiet adventure", description: "A reader-owned entry, with chapters collected from two sources. Local edits, chapter arrangements and reading progress belong to your library.", coverURL: nil, authors: ["Preview author"], status: "ongoing")
            let chapters = [20, 22, 23, 24, 25].map { ChapterRecord(id: "a-\($0)", title: "Chapter \($0)", number: String($0), ordinal: $0, language: "en", groups: ["Source A release"]) }
            let id = try state.library.add(details: details, connectionID: a.id, records: chapters, language: "en", categories: [category.id]); firstID = id
            _ = try state.library.remember(details: MangaDetails(id: "preview-b", title: details.title, description: "", coverURL: nil), connectionID: b.id, records: [ChapterRecord(id: "b-21", title: "A new beginning", number: "21", ordinal: 21, language: "en", groups: ["Source B release"])], complete: true)
            if let chapter = state.library.chapters.last {
                try state.library.copy([CopiedChapter(chapterID: chapter.id)])
                try state.library.paste(entryID: id, revision: 0, choices: state.library.pastePreview(entryID: id))
            }
            try state.markSlots(entryID: id, slots: Set(state.library.entry(id)?.slots.prefix(1).map(\.id) ?? []), read: true)
            try state.library.editEntry(id) { $0.status = .reading }
            _ = try state.library.createManual(title: "Weekend collection", description: "A place for chapters you choose.")
        }
        guard let firstID else { throw LibraryFailure.missing }
        return firstID
    }
}
#endif
