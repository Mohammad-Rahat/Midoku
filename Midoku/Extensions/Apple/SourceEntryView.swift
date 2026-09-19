import SwiftUI

struct SourceEntryView: View {
    let summary: MangaSummary
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @State private var adding = false
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var actionMessage: String?
    @State private var details: MangaDetails?
    @State private var detailError: String?
    @State private var detailRetry = 0
    @State private var loadedDetailRevision: Int?
    @State private var loadedChapterQuery: ChapterQuery?
    @State private var chapterLanguage = ""
    @State private var chapters = SourcePageStore<ChapterRecord>()
    @State private var chapterRetry = 0
    @State private var pageRequest = 0

    nonisolated private struct ChapterQuery: Equatable {
        let language: String
        let revision: Int
    }

    private var chapterQuery: ChapterQuery? {
        guard details != nil, adapter.manifest.capabilities.contains(.chapters) else { return nil }
        return ChapterQuery(language: chapterLanguage, revision: chapterRetry)
    }

    private func chapterIdentity(_ chapter: ChapterRecord) -> SourceChapterIdentity {
        SourceChapterIdentity(listing: SourceListingIdentity(connectionID: adapter.connection.id, externalID: summary.id), externalID: chapter.id)
    }
    private func downloadStatus(_ chapter: ChapterRecord) -> DownloadStatus? {
        downloads.items.first { $0.record.id == chapterIdentity(chapter) && $0.status != .cancelled }?.status
    }
    private func download(_ chapter: ChapterRecord) {
        Task { await downloads.enqueue(ReadingRecord(identity: chapterIdentity(chapter), mangaTitle: details?.title ?? summary.title,
            sourceName: adapter.connection.name, chapter: chapter, openedAt: Date(), coverURL: details?.coverURL ?? summary.coverURL)) }
    }

    private var existingEntries: [PersonalEntry] {
        let identity = SourceListingIdentity(connectionID: adapter.connection.id, externalID: summary.id)
        guard let listing = settings.snapshot.library.listings.first(where: { $0.identity == identity }) else { return [] }
        return settings.snapshot.library.entries.filter { $0.links.contains { $0.listingID == listing.id } }
    }

    var body: some View {
        List {
            Section {
                SourceEntryHeader(summary: summary, details: details, adapter: adapter, extensions: extensions)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
            .listRowBackground(MidokuTheme.surface)
            if let detailError {
                SourceErrorView(message: detailError) { detailRetry += 1 }
                    .listRowBackground(MidokuTheme.surface)
            } else if details == nil {
                ProgressView("Loading entry").listRowBackground(MidokuTheme.surface)
            }
            if let details {
                Section {
                    ForEach(existingEntries) { entry in
                        NavigationLink { LibraryEntryView(entryID: entry.id, extensions: extensions) } label: {
                            Label("Open \(settings.snapshot.library.title(entry))", systemImage: "books.vertical")
                        }
                    }
                    if let actionMessage { Text(actionMessage).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                }.listRowBackground(MidokuTheme.surface)
                Section("About") {
                    SourceDescriptionView(text: details.description)
                    if let authors = details.authors, !authors.isEmpty {
                        LabeledContent("Author", value: authors.formatted(.list(type: .and)))
                    }
                    if let artists = details.artists, !artists.isEmpty, artists != details.authors {
                        LabeledContent("Artist", value: artists.formatted(.list(type: .and)))
                    }
                    if let status = details.status { LabeledContent("Status", value: status.capitalized) }
                    if let year = details.year { LabeledContent("Year", value: year) }
                    if let tags = details.tags, !tags.isEmpty {
                        Text(tags.formatted(.list(type: .and)))
                            .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                    }
                    if let url = details.webURL {
                        Link(destination: url) { Label("View on \(adapter.connection.name)", systemImage: "arrow.up.right.square") }
                    }
                }
                .listRowBackground(MidokuTheme.surface)
            }
            if adapter.manifest.capabilities.contains(.chapters) {
                Section {
                    HStack(spacing: 12) {
                        if let languages = details?.availableLanguages, languages.count > 1, adapter.manifest.contractVersion >= 2 {
                            Picker("Language", selection: $chapterLanguage) {
                                ForEach(languages) { language in Text(language.title).tag(language.id) }
                            }.labelsHidden().accessibilityLabel("Chapter language")
                        } else { Text(chapterLanguage.isEmpty ? "Chapters" : chapterLanguage.uppercased()).font(.subheadline) }
                        Spacer(minLength: 0)
                        Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }.buttonStyle(.borderless)
                        NavigationLink { ClipboardView() } label: {
                            Label("Chapter clipboard", systemImage: "doc.on.clipboard").labelStyle(.iconOnly).frame(width: 44, height: 44)
                        }.buttonStyle(.plain)
                    }
                    if chapters.isLoading { ProgressView("Loading chapters") }
                    if let error = chapters.errorMessage {
                        SourceErrorView(message: error) {
                            if chapters.items.isEmpty || chapters.isStale { chapterRetry += 1 }
                            else { pageRequest += 1 }
                        }
                    }
                    if chapters.isStale {
                        Text("Updating chapters for the selected language.")
                            .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                    } else {
                        ForEach(chapters.items) { chapter in
                            HStack(spacing: 8) {
                                if selecting { Button { if !selected.insert(chapter.id).inserted { selected.remove(chapter.id) } } label: { Image(systemName: selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle").frame(minWidth: 44, minHeight: 44) }.buttonStyle(.borderless).accessibilityLabel("Select \(chapter.title)") }
                                NavigationLink {
                                    ChapterReaderDestination(mangaID: summary.id, mangaTitle: details?.title ?? summary.title,
                                        chapter: chapter, adapter: adapter, extensions: extensions, chapters: chapters.items, coverURL: details?.coverURL ?? summary.coverURL)
                                } label: {
                                    HStack(spacing: 12) {
                                        if settings.snapshot.preferences.chapterThumbnails {
                                            ChapterCoverView(identity: SourceChapterIdentity(listing: SourceListingIdentity(connectionID: adapter.connection.id, externalID: summary.id), externalID: chapter.id), extensions: extensions)
                                                .frame(width: 72, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
                                                .accessibilityHidden(true)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            SourceChapterRow(chapter: chapter)
                                            if let status = downloadStatus(chapter) {
                                                Label(status.title, systemImage: status == .completed ? "checkmark.circle" : "arrow.down.circle")
                                                    .font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                                            }
                                        }
                                    }
                                }.disabled(!adapter.manifest.capabilities.contains(.pages))
                                Menu {
                                    Button("Copy chapter", systemImage: "doc.on.doc") { copy([chapter]) }
                                    Button(settings.snapshot.library.completed.contains(chapterIdentity(chapter)) ? "Mark unread" : "Mark read", systemImage: "checkmark.circle") { mark(chapter) }
                                    Button("Select", systemImage: "checkmark.circle") { selecting = true; selected.insert(chapter.id) }
                                    Button("Download chapter", systemImage: "arrow.down.circle") { download(chapter) }
                                        .disabled(!adapter.manifest.capabilities.contains(.pages) || !downloads.isReady || downloadStatus(chapter) != nil)
                                    NavigationLink("Manage downloads") { DownloadsListView() }
                                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                                    .accessibilityLabel("Chapter actions")
                            }
                            .contextMenu {
                                Button("Download chapter", systemImage: "arrow.down.circle") { download(chapter) }
                                    .disabled(!adapter.manifest.capabilities.contains(.pages) || !downloads.isReady || downloadStatus(chapter) != nil)
                            }
                        }
                    }
                    if chapters.nextCursor != nil {
                        Button("Load more chapters") { pageRequest += 1 }
                            .frame(minHeight: 44)
                            .disabled(chapters.isLoading || chapters.isStale)
                    } else if details != nil, !chapters.isLoading, chapters.items.isEmpty,
                              chapters.errorMessage == nil {
                        Text("No readable chapters in this language.")
                            .foregroundStyle(MidokuTheme.secondaryText)
                    }
                } header: {
                    Text("Chapters")
                } footer: {
                    Text("\(chapters.items.count) chapters loaded · \(adapter.connection.name)")
                }
                .listRowBackground(MidokuTheme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(MidokuTheme.background)
        .modifier(SolidNavigationBar())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let existing = existingEntries.first {
                    NavigationLink { LibraryEntryView(entryID: existing.id, extensions: extensions) } label: {
                        Label("In library", systemImage: "checkmark").labelStyle(.titleAndIcon)
                    }
                } else {
                    Button { addToLibrary() } label: {
                        if adding { ProgressView() }
                        else { Label("Add to library", systemImage: "plus").labelStyle(.titleAndIcon) }
                    }.disabled(details == nil || adding)
                }
            }.sharedBackgroundVisibility(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Button("Select loaded") { selected = Set(chapters.items.map(\.id)) }
                    Spacer()
                    Button("Copy (\(selected.count))") { copy(chapters.items.filter { selected.contains($0.id) }) }.disabled(selected.isEmpty)
                }.padding().background(MidokuTheme.surface)
            }
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: detailRetry) {
            guard loadedDetailRevision != detailRetry else { return }
            do {
                _ = try await extensions.adapter(for: adapter.connection)
                let result = try await adapter.details(mangaID: summary.id)
                try Task.checkCancellation()
                chapterLanguage = summary.preferredChapterLanguage ?? result.defaultChapterLanguage ?? ""
                details = result
                detailError = nil
                loadedDetailRevision = detailRetry
            } catch {
                if !Task.isCancelled {
                    detailError = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription
                }
            }
        }
        .task(id: chapterQuery) {
            guard let chapterQuery, loadedChapterQuery != chapterQuery else { return }
            let language = chapterQuery.language.isEmpty ? nil : chapterQuery.language
            await chapters.replace {
                let current = try await extensions.adapter(for: adapter.connection)
                return try await current.chapters(mangaID: summary.id, cursor: nil, language: language)
            }
            if !Task.isCancelled, chapters.errorMessage == nil { loadedChapterQuery = chapterQuery }
        }
        .task(id: pageRequest) {
            guard pageRequest > 0, let chapterQuery else { return }
            let language = chapterQuery.language.isEmpty ? nil : chapterQuery.language
            await chapters.loadMore { cursor in
                let current = try await extensions.adapter(for: adapter.connection)
                return try await current.chapters(mangaID: summary.id, cursor: cursor, language: language)
            }
        }
    }
    private func addToLibrary() {
        guard let details, !adding else { return }
        adding = true; actionMessage = nil
        let records = chapters.isStale ? [] : chapters.items
        let language = chapterLanguage.isEmpty ? nil : chapterLanguage
        Task {
            do {
                let id = try await library.addVisible(details: details, connection: adapter.connection, records: records, language: language)
                adding = false
                actionMessage = "Added to library. Checking for the remaining chapters…"
                await library.refresh(entryIDs: [id])
                actionMessage = library.refreshMessage
            } catch { adding = false; actionMessage = error.localizedDescription }
        }
    }
    private func copy(_ records: [ChapterRecord]) {
        guard let details else { return }
        Task {
            do { try await library.copy(details: details, connection: adapter.connection, chapters: records); actionMessage = "Copied \(records.count) chapters. Open the clipboard to choose a library entry."; selecting = false; selected.removeAll() }
            catch { actionMessage = error.localizedDescription }
        }
    }
    private func mark(_ chapter: ChapterRecord) {
        let id = chapterIdentity(chapter)
        settings.update { state in
            if state.library.completed.contains(id) { state.library.completed.remove(id); state.progress.removeAll { $0.id == id } }
            else { state.library.completed.insert(id) }
        }
    }

}

private struct SourceEntryHeader: View {
    let summary: MangaSummary
    let details: MangaDetails?
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            SourceCoverView(url: details?.coverURL ?? summary.coverURL, adapter: adapter, extensions: extensions)
                .frame(width: 110, height: 165).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 10) {
                Text(details?.title ?? summary.title).font(.title2.bold()).textSelection(.enabled)
                Label(adapter.connection.name, systemImage: "globe")
                    .font(.subheadline).foregroundStyle(MidokuTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SourceDescriptionView: View {
    let text: String
    @State private var expanded = false
    @State private var attributed = AttributedString()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if text.isEmpty {
                Text("No description available.").foregroundStyle(MidokuTheme.secondaryText)
            } else {
                Text(attributed).lineLimit(expanded ? nil : 5).textSelection(.enabled)
                Button(expanded ? "Show less" : "Read description") { expanded.toggle() }
                    .font(.subheadline).frame(minHeight: 44)
            }
        }
        .task(id: text) {
            attributed = (try? AttributedString(markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        }
    }
}

private struct SourceChapterRow: View {
    let chapter: ChapterRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let number = chapter.number {
                Text("Chapter \(number)").font(.headline)
            }
            Text(chapter.title).font(.subheadline).foregroundStyle(MidokuTheme.primaryText)
            if let groups = chapter.groups, !groups.isEmpty {
                Text(groups.formatted(.list(type: .and)))
                    .font(.caption).foregroundStyle(MidokuTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

