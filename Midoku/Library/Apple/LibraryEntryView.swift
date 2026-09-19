import SwiftUI

struct LibraryEntryView: View {
    let entryID: UUID
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var sources = false
    @State private var pasting = false
    @State private var removing = false
    @State private var resetting = false
    @State private var selecting = false
    @State private var originalListing: LibraryListing?
    @State private var readingSlot: UUID?
    @Environment(\.gridLandscape) private var landscape
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selected: Set<UUID> = []
    @State private var filter = "all"
    @State private var sourceID: UUID?
    @State private var language = "all"
    @State private var group = "all"
    @State private var renamedSlot: ChapterSlot?
    @State private var editedSlot: ChapterSlot?
    @State private var alternatives: ChapterSlot?
    @State private var message: String?
    @State private var deleteChapters = false
    private var state: LibraryState { settings.snapshot.library }
    private var entry: PersonalEntry? { state.entry(entryID) }

    private var grid: Bool { settings.snapshot.preferences.resolvedChapterLayout.style == .grid && !textSize.isAccessibilitySize }

    var body: some View {
        Group {
            if let entry {
                ScrollViewReader { proxy in
                List {
                    Group {
                        VStack(alignment: .leading, spacing: 12) {
                            header(entry)
                            EntrySynopsis(text: state.description(entry))
                        }.padding(.top, 4).padding(.bottom, 4)
                    }.listRowBackground(MidokuTheme.background).listRowSeparator(.hidden)
                    if let error = entry.links.compactMap({ state.listing($0.listingID)?.lastError }).first {
                        Section { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(MidokuTheme.secondaryText) }.listRowBackground(MidokuTheme.surface)
                    }
                    if let message { Section { Text(message).font(.caption) }.listRowBackground(MidokuTheme.surface) }
                    Group {
                        HStack {
                            Text("\(entry.slots.count) chapters").font(.subheadline.weight(.semibold))
                            Spacer()
                            filters(entry)
                            if !state.clipboard.isEmpty {
                                Button { pasting = true } label: { Label("Paste chapters", systemImage: "doc.on.clipboard").labelStyle(.iconOnly) }.buttonStyle(MidokuIconButtonStyle())
                            }
                            Button { selecting.toggle(); selected.removeAll() } label: {
                                Label(selecting ? "Finish selection" : "Select chapters", systemImage: selecting ? "checkmark" : "checkmark.circle")
                                    .labelStyle(.iconOnly)
                            }.buttonStyle(MidokuIconButtonStyle())
                        }.id("chapter-header").listRowSeparator(.hidden)
                        if entry.slots.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your next read starts here").font(.headline)
                                Text("Copy chapters from Browse, then paste them into this entry.").font(.callout).foregroundStyle(MidokuTheme.secondaryText)
                                if !state.clipboard.isEmpty { Button("Paste from clipboard") { pasting = true } }
                                NavigationLink("Find chapters") { SourceDirectoryView(extensions: extensions) }
                            }.padding(.vertical, 8)
                        }
                        if grid {
                            ChapterGridRows(items: visibleSlots(entry), columns: settings.snapshot.preferences.resolvedChapterLayout.columns(landscape: landscape)) { slot in
                                chapterCard(slot, entry: entry)
                            }
                        } else { ForEach(visibleSlots(entry)) { slot in chapterRow(slot, entry: entry) } }
                        if !entry.slots.isEmpty && visibleSlots(entry).isEmpty { Text("No chapters match these filters.").foregroundStyle(MidokuTheme.secondaryText) }
                    }.listRowBackground(MidokuTheme.background)
                }.modifier(EntryListStyle()).refreshable { await library.refresh(entryIDs: [entryID]) }
                #if DEBUG
                .task {
                    if ["--chapters-preview", "--chapter-grid-preview", "--chapter-compact-preview", "--chapter-thumbnail-preview", "--empty-clipboard-preview"].contains(where: CommandLine.arguments.contains) {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo("chapter-header", anchor: .top)
                    }
                }
                #endif
                }
            } else { ContentUnavailableView("Entry removed", systemImage: "books.vertical", description: Text("Shared progress and downloads have been kept.")) }
        }
        .navigationTitle(selecting ? "\(selected.count) selected" : "Library entry").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if library.refreshing { ProgressView() }
                Menu {
                    Button("Edit details", systemImage: "pencil") { editing = true }
                    Button("Reset details", systemImage: "arrow.counterclockwise") { resetting = true }
                    Button("Manage sources", systemImage: "link") { sources = true }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await library.refresh(entryIDs: [entryID]) } }.disabled(library.refreshing)
                    if !state.clipboard.isEmpty { Button("Paste chapters (\(state.clipboard.count))", systemImage: "doc.on.clipboard") { pasting = true } }
                    NavigationLink { RemovedChaptersView(entryID: entryID) } label: { Label("Removed chapters", systemImage: "arrow.uturn.backward") }
                    Button("Restore automatic reading order", systemImage: "arrow.up.arrow.down") { change { try $0.library.editEntry(entryID) { $0.manualOrder = false } } }
                    Button("Remove from library", systemImage: "trash", role: .destructive) { removing = true }
                } label: { Image(systemName: "ellipsis").accessibilityLabel("Entry actions") }.disabled(entry == nil)
            }
        }
        #if DEBUG
        .onAppear {
            if CommandLine.arguments.contains("--rename-preview"), renamedSlot == nil { renamedSlot = entry?.slots.first }
        }
        #endif
        .modifier(OriginalListingNavigation(listing: $originalListing, extensions: extensions))
        .navigationDestination(isPresented: Binding(get: { readingSlot != nil }, set: { if !$0 { readingSlot = nil } })) {
            if let readingSlot { LibraryReaderView(entryID: entryID, initialSlotID: readingSlot, extensions: extensions) }
        }
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .sheet(isPresented: $editing) { if let entry { EntryEditor(entry: entry, extensions: extensions) } }
        .sheet(isPresented: $sources) { EntrySourcesView(entryID: entryID, extensions: extensions) }
        .sheet(isPresented: $pasting) { PasteReviewView(entryID: entryID) }
        .sheet(item: $renamedSlot) { slot in ChapterEditor(entryID: entryID, slotID: slot.id, renameOnly: true) }
        .sheet(item: $editedSlot) { slot in ChapterEditor(entryID: entryID, slotID: slot.id) }
        .sheet(item: $alternatives) { slot in AlternativesView(entryID: entryID, slotID: slot.id) }
        .confirmationDialog("Reset entry details?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset details", role: .destructive) { change { try $0.library.resetDetails(entryID) } }
        } message: { Text("Restore source titles, descriptions, authors, entry and chapter covers, chapter names, reader defaults, and automatic order. All added chapters, source links, categories, and reading progress are kept.") }
        .confirmationDialog("Remove this entry?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove from library", role: .destructive) { Task { do { try await settings.commit { $0.library.removeEntries([entryID]) }; dismiss() } catch { message = error.localizedDescription } } }
        } message: { Text("Downloads, History, and shared progress are kept. Only this entry and its chapter arrangement are removed.") }
        .confirmationDialog("Remove selected chapters?", isPresented: $deleteChapters, titleVisibility: .visible) {
            Button("Remove chapters", role: .destructive) { let ids = selected; change { try $0.library.removeSlots(entryID: entryID, slotIDs: ids) }; selected.removeAll(); selecting = false }
        } message: { Text("They stay excluded during refresh. You can restore them from Removed chapters. Shared downloads and progress are kept.") }
    }

    private func header(_ entry: PersonalEntry) -> some View {
        let metadata = state.listing(entry.primaryListingID)?.details
        let status = [entry.status.title, metadata?.status?.capitalized].compactMap { $0 }
        let categories = settings.snapshot.categories.filter { entry.categoryIDs.contains($0.id) }.map(\.name)
            .filter { category in !status.contains { $0.localizedCaseInsensitiveCompare(category) == .orderedSame } }
        return EntryOverview(title: state.title(entry), author: entry.authorOverride ?? metadata?.authors?.joined(separator: ", "),
            metadata: (status + categories).joined(separator: " · "),
            detail: "\(entry.slots.filter { !state.isRead($0) }.count) unread") {
                LibraryCoverView(entry: entry, extensions: extensions)
            } action: {
            if let slot = state.resumeSlot(entry, positions: settings.snapshot.progress) {
                Button { readingSlot = slot } label: {
                    Label(entry.lastReadAt == nil ? "Start reading" : "Continue reading", systemImage: "play.fill")
                }
            }
        }
    }

    private func visibleSlots(_ entry: PersonalEntry) -> [ChapterSlot] {
        let downloaded = Set(downloads.items.filter { $0.status == .completed }.map { $0.record.id })
        let slots = entry.slots.filter { slot in
            guard let variant = slot.preferred, let chapter = state.chapter(variant.chapterID) else { return false }
            return (filter == "all" || (filter == "read" ? state.isRead(slot) : filter == "unread" ? !state.isRead(slot) : downloaded.contains(chapter.identity))) &&
                (sourceID == nil || chapter.identity.listing.connectionID == sourceID) &&
                (language == "all" || chapter.record.language == language) && (group == "all" || chapter.record.groups?.contains(group) == true)
        }
        return entry.descendingDisplay ? Array(slots.reversed()) : slots
    }
    private func filters(_ entry: PersonalEntry) -> some View {
        Menu {
            Picker("Show", selection: $filter) { Text("All").tag("all"); Text("Unread").tag("unread"); Text("Read").tag("read"); Text("Downloaded").tag("downloaded") }
            Picker("Source", selection: $sourceID) {
                Text("All sources").tag(UUID?.none)
                ForEach(settings.snapshot.connections.filter { connection in entry.links.contains { state.listing($0.listingID)?.identity.connectionID == connection.id } }) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Language", selection: $language) { Text("All languages").tag("all"); ForEach(Array(Set(entry.slots.flatMap(\.variants).compactMap { state.chapter($0.chapterID)?.record.language })).sorted(), id: \.self) { Text($0).tag($0) } }
            Picker("Group", selection: $group) { Text("All groups").tag("all"); ForEach(Array(Set(entry.slots.flatMap(\.variants).flatMap { state.chapter($0.chapterID)?.record.groups ?? [] })).sorted(), id: \.self) { Text($0).tag($0) } }
            Button(entry.descendingDisplay ? "Show ascending" : "Show descending", systemImage: "arrow.up.arrow.down") { change { try $0.library.editEntry(entryID) { $0.descendingDisplay.toggle() } } }
        } label: { Label("Filters", systemImage: "line.3.horizontal.decrease") }.labelStyle(.iconOnly).buttonStyle(MidokuIconButtonStyle())
    }
    @ViewBuilder private func chapterRow(_ slot: ChapterSlot, entry: PersonalEntry) -> some View {
        if let variant = slot.preferred, let chapter = state.chapter(variant.chapterID) {
            HStack(spacing: 8) {
                if selecting { Button { toggle(slot.id) } label: { rowLabel(slot, variant: variant, chapter: chapter, entry: entry) }.buttonStyle(.plain) }
                else { NavigationLink { LibraryReaderView(entryID: entryID, initialSlotID: slot.id, extensions: extensions) } label: { rowLabel(slot, variant: variant, chapter: chapter, entry: entry) } }
            }.contextMenu {
                chapterActions(slot, chapter: chapter, entry: entry)
            }
        }
    }
    private func chapterActions(_ slot: ChapterSlot, chapter: LibraryChapter, entry: PersonalEntry) -> some View {
        Group {
            Button("Copy chapter", systemImage: "doc.on.doc") { copy([slot.id]) }
            Button("Rename chapter", systemImage: "character.cursor.ibeam") { renamedSlot = slot }
            Button("Edit chapter", systemImage: "pencil") { editedSlot = slot }
            Button(state.isRead(slot) ? "Mark unread" : "Mark read", systemImage: "checkmark.circle") { let read = !state.isRead(slot); change { try $0.markSlots(entryID: entryID, slots: [slot.id], read: read) } }
            Button("Download", systemImage: "arrow.down.circle") { download([slot.id]) }
            Button("Alternatives (\(slot.variants.count))", systemImage: "square.stack") { alternatives = slot }
            Button("Move earlier", systemImage: "arrow.up") { change { try $0.library.moveSlot(entryID: entryID, slotID: slot.id, offset: -1) } }.disabled(entry.slots.first?.id == slot.id)
            Button("Move later", systemImage: "arrow.down") { change { try $0.library.moveSlot(entryID: entryID, slotID: slot.id, offset: 1) } }.disabled(entry.slots.last?.id == slot.id)
            if let listing = state.listings.first(where: { $0.identity == chapter.identity.listing }) { Button("Open original listing", systemImage: "arrow.up.right.square") { originalListing = listing } }
            Button("Select", systemImage: "checkmark.circle") { selecting = true; selected.insert(slot.id) }
            Button("Remove from this entry", systemImage: "trash", role: .destructive) { selected = [slot.id]; deleteChapters = true }
        }
    }

    @ViewBuilder private func chapterCard(_ slot: ChapterSlot, entry: PersonalEntry) -> some View {
        if let variant = slot.preferred, let chapter = state.chapter(variant.chapterID) {
            VStack(alignment: .leading, spacing: 4) {
                if selecting {
                    Button { toggle(slot.id) } label: { chapterCardLabel(slot, variant: variant, chapter: chapter) }.buttonStyle(.plain)
                } else {
                    Button { readingSlot = slot.id } label: {
                        chapterCardLabel(slot, variant: variant, chapter: chapter)
                    }.buttonStyle(.plain).accessibilityHint("Opens chapter")
                }
            }.contextMenu { chapterActions(slot, chapter: chapter, entry: entry) }
                .accessibilityAction(named: "Select chapter") { selecting = true; selected.insert(slot.id) }
                .accessibilityAction(named: "Rename chapter") { renamedSlot = slot }
                .accessibilityAction(named: "Copy chapter") { copy([slot.id]) }
        }
    }

    private func chapterCardLabel(_ slot: ChapterSlot, variant: ChapterVariant, chapter: LibraryChapter) -> some View {
        let source = settings.snapshot.connections.first { $0.id == chapter.identity.listing.connectionID }?.name ?? "Unavailable source"
        return ChapterGridLabel(title: state.chapterDisplayTitle(variant),
            subtitle: variant.edits.title == nil && state.number(variant) != nil ? state.chapterTitle(variant) : nil,
            detail: source, style: settings.snapshot.preferences.resolvedChapterLayout.resolvedGridStyle,
            showsCover: settings.snapshot.preferences.chapterThumbnails, selected: selecting ? selected.contains(slot.id) : nil) {
                ChapterCoverView(identity: chapter.identity, extensions: extensions, overrideID: variant.edits.coverID)
            }
    }

    private func rowLabel(_ slot: ChapterSlot, variant: ChapterVariant, chapter: LibraryChapter, entry: PersonalEntry) -> some View {
        HStack(spacing: 12) {
            if selecting { Image(systemName: selected.contains(slot.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
            if settings.snapshot.preferences.chapterThumbnails { ChapterCoverView(identity: chapter.identity, extensions: extensions, overrideID: variant.edits.coverID).frame(width: 56, height: 84).clipped().clipShape(RoundedRectangle(cornerRadius: 6)) }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(state.chapterDisplayTitle(variant)).font(.subheadline.weight(.semibold))
                    if state.isRead(slot) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Read") }
                }
                if variant.edits.title == nil, state.number(variant) != nil { Text(state.chapterTitle(variant)).font(.caption).lineLimit(2) }
                let source = settings.snapshot.connections.first { $0.id == chapter.identity.listing.connectionID }?.name ?? "Unavailable source"
                Text(([source, chapter.record.language] + (chapter.record.groups ?? []).map(Optional.some)).compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(MidokuTheme.secondaryText)
                if let volume = variant.edits.volume ?? chapter.record.volume, !volume.isEmpty { Text("Volume \(volume)").font(.caption2).foregroundStyle(MidokuTheme.secondaryText) }
                if let download = downloads.items.first(where: { $0.record.id == chapter.identity && $0.status != .cancelled }) { Text(download.status.title).font(.caption2).foregroundStyle(.tint) }
                if !chapter.available { Text("Unavailable at source · saved reference kept").font(.caption2).foregroundStyle(MidokuTheme.secondaryText) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 3).foregroundStyle(MidokuTheme.primaryText)
    }
    private var selectionBar: some View {
        HStack {
            Button("Select all") { if let entry { selected = Set(visibleSlots(entry).map(\.id)) } }
            Spacer()
            Menu("Actions", systemImage: "ellipsis.circle") {
                Button("Copy \(selected.count) chapters") { copy(selected) }
                Button("Mark read") { let ids = selected; change { try $0.markSlots(entryID: entryID, slots: ids, read: true) } }
                Button("Mark unread") { let ids = selected; change { try $0.markSlots(entryID: entryID, slots: ids, read: false) } }
                Button("Download") { download(selected) }
                Button("Remove", role: .destructive) { deleteChapters = true }
            }.disabled(selected.isEmpty)
        }.padding(16).background(MidokuTheme.surface)
    }
    private func toggle(_ id: UUID) { if !selected.insert(id).inserted { selected.remove(id) } }
    private func change(_ action: @escaping (inout AppSnapshot) throws -> Void) { Task { do { try await settings.commit(action) } catch { message = error.localizedDescription } } }
    private func copy(_ ids: Set<UUID>) {
        guard let entry else { return }
        let items = entry.slots.filter { ids.contains($0.id) }.compactMap(\.preferred).map { CopiedChapter(chapterID: $0.chapterID, edits: $0.edits) }
        Task { do { try await settings.commit { try $0.library.copy(items) }; message = "Copied \(items.count) chapter\(items.count == 1 ? "" : "s") to Midoku's clipboard." } catch { message = error.localizedDescription } }
    }
    private func download(_ ids: Set<UUID>) {
        guard let entry else { return }
        let records = entry.slots.filter { ids.contains($0.id) }.compactMap { slot in slot.preferred.flatMap { state.readingRecord($0.chapterID, connections: settings.snapshot.connections, entryID: entryID, slotID: slot.id) } }
        Task { for record in records { await downloads.enqueue(record) } }
    }
}
