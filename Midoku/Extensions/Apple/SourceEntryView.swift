import SwiftUI

struct SourceEntryView: View {
    let summary: MangaSummary
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
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
                    if let languages = details?.availableLanguages, languages.count > 1,
                       adapter.manifest.contractVersion >= 2 {
                        Picker("Chapter language", selection: $chapterLanguage) {
                            ForEach(languages) { language in
                                Text(language.title).tag(language.id)
                            }
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
                        ForEach(chapters.items) { chapter in
                            NavigationLink {
                                SourceChapterReader(mangaID: summary.id, mangaTitle: details?.title ?? summary.title,
                                                    chapter: chapter, adapter: adapter, extensions: extensions)
                            } label: {
                                SourceChapterRow(chapter: chapter)
                            }
                            .disabled(!adapter.manifest.capabilities.contains(.pages))
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
