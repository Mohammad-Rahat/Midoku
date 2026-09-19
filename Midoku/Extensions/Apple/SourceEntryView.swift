import SwiftUI

struct SourceEntryView: View {
    let summary: MangaSummary
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @Environment(\.gridLandscape) private var landscape
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showingAdd = false
    @State private var showingMetadata = false
    @State private var selecting = false
    @State private var showingClipboard = false
    @State private var readingChapter: ChapterRecord?
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

    private var grid: Bool { settings.snapshot.preferences.resolvedChapterLayout.style == .grid && !textSize.isAccessibilitySize }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    SourceEntryHeader(summary: summary, details: details, adapter: adapter, extensions: extensions)
                    if let details { EntrySynopsis(text: details.description) }
                    if details != nil {
                        Button { showingMetadata = true } label: { Label("Details", systemImage: "info.circle").font(.caption) }
                            .buttonStyle(.plain).foregroundStyle(.tint)
                    }
                }.padding(.top, 4).padding(.bottom, 4)
            }
            .listRowBackground(MidokuTheme.background).listRowSeparator(.hidden)
            if let detailError {
                SourceErrorView(message: detailError) { detailRetry += 1 }
                    .listRowBackground(MidokuTheme.surface)
            } else if details == nil {
                ProgressView("Loading entry").listRowBackground(MidokuTheme.surface)
            }
            if details != nil, !existingEntries.isEmpty || actionMessage != nil {
                Section {
                    ForEach(existingEntries) { entry in
                        NavigationLink { LibraryEntryView(entryID: entry.id, extensions: extensions) } label: {
                            Label("Open \(settings.snapshot.library.title(entry))", systemImage: "books.vertical")
                        }
                    }
                    if let actionMessage { Text(actionMessage).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                }.listRowBackground(MidokuTheme.background)
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
                        Button { selecting.toggle(); selected.removeAll() } label: {
                            Label(selecting ? "Finish selection" : "Select chapters", systemImage: selecting ? "checkmark" : "checkmark.circle").labelStyle(.iconOnly)
                        }.buttonStyle(MidokuIconButtonStyle())
                        if !settings.snapshot.library.clipboard.isEmpty {
                            Button { showingClipboard = true } label: {
                                Label("Chapter clipboard", systemImage: "doc.on.clipboard").labelStyle(.iconOnly)
                            }.buttonStyle(MidokuIconButtonStyle())
                        }
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
                        if grid {
                            ChapterGridRows(items: chapters.items, columns: settings.snapshot.preferences.resolvedChapterLayout.columns(landscape: landscape)) { chapter in
                                chapterCard(chapter)
                            }
                        } else { ForEach(chapters.items) { chapter in chapterRow(chapter) } }
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
                }.listRowBackground(MidokuTheme.background)
            }
        }
        .modifier(EntryListStyle())
        .sheet(isPresented: $showingAdd) {
            if let details {
                AddToLibrarySheet(title: details.title, source: adapter.connection.name,
                    language: chapterLanguage.isEmpty ? nil : chapterLanguage, save: addToLibrary)
            }
        }
        .sheet(isPresented: $showingMetadata) { metadataSheet }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let existing = existingEntries.first {
                    NavigationLink { LibraryEntryView(entryID: existing.id, extensions: extensions) } label: {
                        Label("In library", systemImage: "checkmark").labelStyle(.titleAndIcon)
                    }
                } else {
                    Button { showingAdd = true } label: {
                        Label("Add to library", systemImage: "plus").labelStyle(.iconOnly)
                    }.disabled(details == nil)
                }
            }
        }
        .navigationDestination(isPresented: $showingClipboard) { ClipboardView() }
        .navigationDestination(isPresented: Binding(get: { readingChapter != nil }, set: { if !$0 { readingChapter = nil } })) {
            if let readingChapter { reader(readingChapter) }
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
        #if DEBUG
        .onChange(of: loadedDetailRevision) {
            if CommandLine.arguments.contains("--add-entry-preview"), loadedDetailRevision != nil { showingAdd = true }
        }
        #endif
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
    private func reader(_ chapter: ChapterRecord) -> some View {
        ChapterReaderDestination(mangaID: summary.id, mangaTitle: details?.title ?? summary.title,
            chapter: chapter, adapter: adapter, extensions: extensions, chapters: chapters.items, coverURL: details?.coverURL ?? summary.coverURL)
    }
    private func toggle(_ chapter: ChapterRecord) {
        if !selected.insert(chapter.id).inserted { selected.remove(chapter.id) }
    }
    private func chapterActions(_ chapter: ChapterRecord) -> some View {
        Group {
            Button("Copy chapter", systemImage: "doc.on.doc") { copy([chapter]) }
            Button(settings.snapshot.library.completed.contains(chapterIdentity(chapter)) ? "Mark unread" : "Mark read", systemImage: "checkmark.circle") { mark(chapter) }
            Button("Select", systemImage: "checkmark.circle") { selecting = true; selected.insert(chapter.id) }
            Button("Download chapter", systemImage: "arrow.down.circle") { download(chapter) }
                .disabled(!adapter.manifest.capabilities.contains(.pages) || !downloads.isReady || downloadStatus(chapter) != nil)
            NavigationLink("Manage downloads") { DownloadsListView() }
        }
    }
    private func chapterRow(_ chapter: ChapterRecord) -> some View {
        HStack(spacing: 8) {
            if selecting {
                Button { toggle(chapter) } label: {
                    Image(systemName: selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle").frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderless).accessibilityLabel("Select \(chapter.title)")
            }
            NavigationLink { reader(chapter) } label: {
                HStack(spacing: 12) {
                    if settings.snapshot.preferences.chapterThumbnails {
                        ChapterCoverView(identity: chapterIdentity(chapter), extensions: extensions)
                            .frame(width: 56, height: 84).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        SourceChapterRow(chapter: chapter)
                        if let status = downloadStatus(chapter) { Text(status.title).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                    }
                }
            }.disabled(!adapter.manifest.capabilities.contains(.pages))
        }.contextMenu { chapterActions(chapter) }
    }
    private func chapterCard(_ chapter: ChapterRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if selecting {
                Button { toggle(chapter) } label: { chapterCardLabel(chapter) }.buttonStyle(.plain)
            } else {
                Button { readingChapter = chapter } label: { chapterCardLabel(chapter) }
                    .buttonStyle(.plain).disabled(!adapter.manifest.capabilities.contains(.pages)).accessibilityHint("Opens chapter")
            }
        }.contextMenu { chapterActions(chapter) }
            .accessibilityAction(named: "Select chapter") { selecting = true; selected.insert(chapter.id) }
            .accessibilityAction(named: "Copy chapter") { copy([chapter]) }
    }
    private func chapterCardLabel(_ chapter: ChapterRecord) -> some View {
        ChapterGridLabel(title: chapter.number.map { "Chapter \($0)" } ?? chapter.title,
            subtitle: chapter.number != nil ? chapter.title : nil,
            detail: ([adapter.connection.name] + (chapter.groups ?? [])).joined(separator: " · "),
            style: settings.snapshot.preferences.resolvedChapterLayout.resolvedGridStyle,
            showsCover: settings.snapshot.preferences.chapterThumbnails, selected: selecting ? selected.contains(chapter.id) : nil) {
                ChapterCoverView(identity: chapterIdentity(chapter), extensions: extensions)
            }
    }

    private func addToLibrary(_ options: LibraryAddOptions) async throws {
        guard let details else { throw LibraryFailure.missing }
        let records = chapters.isStale || loadedChapterQuery?.language != chapterLanguage ? [] : chapters.items
        let language = chapterLanguage.isEmpty ? nil : chapterLanguage
        let id = try await library.addVisible(details: details, connection: adapter.connection,
            records: records, language: language, options: options)
        actionMessage = nil
        Task {
            await library.refresh(entryIDs: [id])
            actionMessage = library.refreshMessage
        }
    }

    private var metadataSheet: some View {
        NavigationStack {
            List {
                if let details {
                    Section {
                        Text(details.title).font(.headline)
                        if let authors = details.authors, !authors.isEmpty { LabeledContent("Author", value: authors.joined(separator: ", ")) }
                        if let artists = details.artists, !artists.isEmpty, artists != details.authors { LabeledContent("Artist", value: artists.joined(separator: ", ")) }
                        if let status = details.status { LabeledContent("Status", value: status.capitalized) }
                        if let year = details.year { LabeledContent("Year", value: year) }
                        if let tags = details.tags, !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.subheadline) }
                        if let url = details.webURL { InAppBrowserLink(url: url, title: "View on \(adapter.connection.name)") }
                    }.listRowBackground(MidokuTheme.surface)
                }
            }.settingsStyle().navigationTitle("Details")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingMetadata = false } } }
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

    var body: some View {
        EntryOverview(title: details?.title ?? summary.title, author: details?.authors?.joined(separator: ", "),
            metadata: [adapter.connection.name, details?.status?.capitalized, details?.year].compactMap { $0 }.joined(separator: " · "),
            detail: nil) {
            SourceCoverView(url: details?.coverURL ?? summary.coverURL, adapter: adapter, extensions: extensions)
        } action: { EmptyView() }
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
