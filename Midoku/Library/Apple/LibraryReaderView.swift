import SwiftUI

/// Navigation follows the entry's canonical slots, independent of display sort and filters.
struct LibraryReaderView: View {
    let entryID: UUID
    let initialSlotID: UUID
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    @State private var currentSlotID: UUID?
    @State private var adapter: (any SourceAdapter)?
    @State private var error: String?
    @State private var retry = 0
    @State private var alternatives = false
    @State private var controlsVisible = true
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private var state: LibraryState { settings.snapshot.library }
    private var entry: PersonalEntry? { state.entry(entryID) }
    private var slotID: UUID { currentSlotID ?? initialSlotID }
    private var slot: ChapterSlot? { entry?.slots.first { $0.id == slotID } }
    private var chapter: LibraryChapter? { slot?.preferred.flatMap { state.chapter($0.chapterID) } }
    private var saved: SavedDownload? { downloads.items.first { $0.record.id == chapter?.identity && $0.status == .completed } }
    private var request: String { "\(chapter?.id.uuidString ?? "missing")-\(retry)" }
    var body: some View {
        Group {
            if let entry, let chapter {
                if let saved { OfflineChapterReader(download: saved, entryID: entryID, slotID: slotID).id(chapter.identity) }
                else if let adapter, adapter.connection.id == chapter.identity.listing.connectionID {
                    SourceChapterReader(mangaID: chapter.identity.listing.externalID, mangaTitle: state.title(entry), chapter: chapter.record,
                                        adapter: adapter, extensions: extensions, entryID: entryID, slotID: slotID).id(chapter.identity)
                } else if let error {
                    VStack(spacing: 16) {
                        ContentUnavailableView("Chapter unavailable", systemImage: "exclamationmark.circle", description: Text(error))
                        Button("Retry") { retry += 1 }.buttonStyle(.borderedProminent)
                        if (slot?.variants.count ?? 0) > 1 { Button("Choose an alternative") { alternatives = true } }
                        NavigationLink("Manage extensions") { ExtensionManagementView(extensions: extensions) }
                    }
                } else { ProgressView("Opening chapter") }
            } else { ContentUnavailableView("Chapter removed", systemImage: "book.closed", description: Text("Return to the entry to choose another chapter. Your saved progress is kept.")) }
        }
        .safeAreaInset(edge: .bottom) {
            if controlsVisible || voiceOver, let entry, let index = entry.slots.firstIndex(where: { $0.id == slotID }) {
                HStack(spacing: 12) {
                    Button { go(entry.slots[index - 1].id) } label: { Label("Previous chapter", systemImage: "backward.end") }.disabled(index == 0)
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text("\(index + 1) of \(entry.slots.count)").font(.caption).monospacedDigit()
                        if index + 1 == entry.slots.count { Text("Last chapter").font(.caption2).foregroundStyle(MidokuTheme.secondaryText) }
                    }
                    Spacer(minLength: 0)
                    Button { go(entry.slots[index + 1].id) } label: { Label("Next chapter", systemImage: "forward.end") }.disabled(index + 1 == entry.slots.count)
                }.labelStyle(.iconOnly).frame(minHeight: 44).padding(.horizontal, 20).background(MidokuTheme.surface)
            }
        }
        .preference(key: AppTabBarHiddenPreference.self, value: true)
        .environment(\.readerChapterNavigation, chapterNavigation)
        .environment(\.readerCoverContext, ReaderCoverContext(entryID: entryID, slotID: slotID))
        .onPreferenceChange(ReaderControlsPreference.self) { controlsVisible = $0 }
        .sheet(isPresented: $alternatives) { AlternativesView(entryID: entryID, slotID: slotID) }
        .task(id: request) {
            adapter = nil; error = nil
            guard let chapter, saved == nil else { return }
            guard let connection = settings.snapshot.connections.first(where: { $0.id == chapter.identity.listing.connectionID }) else { error = "Restore the source to read online. Saved downloads remain readable."; return }
            do {
                let source = try await extensions.adapter(for: connection)
                try Task.checkCancellation()
                adapter = source
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private var chapterNavigation: ReaderChapterNavigation {
        guard let entry, let index = entry.slots.firstIndex(where: { $0.id == slotID }) else { return ReaderChapterNavigation() }
        let previous = index > 0 ? entry.slots[index - 1] : nil
        let next = index + 1 < entry.slots.count ? entry.slots[index + 1] : nil
        return ReaderChapterNavigation(title: slot?.preferred.map { state.chapterDisplayTitle($0) },
            previousTitle: previous?.preferred.map { state.chapterDisplayTitle($0) },
            nextTitle: next?.preferred.map { state.chapterDisplayTitle($0) },
            previous: previous.map { item in { go(item.id) } }, next: next.map { item in { go(item.id) } })
    }
    private func go(_ id: UUID) { adapter = nil; error = nil; currentSlotID = id }
}
