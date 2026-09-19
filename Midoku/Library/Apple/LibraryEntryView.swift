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
    @State private var selected: Set<UUID> = []
    @State private var filter = "all"
    @State private var sourceID: UUID?
    @State private var language = "all"
    @State private var group = "all"
    @State private var expanded = false
    @State private var renamedSlot: ChapterSlot?
    @State private var editedSlot: ChapterSlot?
    @State private var alternatives: ChapterSlot?
    @State private var message: String?
    @State private var deleteChapters = false
    private var state: LibraryState { settings.snapshot.library }
    private var entry: PersonalEntry? { state.entry(entryID) }

    var body: some View {
        Group {
            if let entry {
                List {
                    Section { header(entry) }.listRowBackground(MidokuTheme.surface)
                    if !state.description(entry).isEmpty {
                        Section {
                            Text(state.description(entry)).font(.callout).lineLimit(expanded ? nil : 3).textSelection(.enabled)
                            Button(expanded ? "Show less" : "Read description") { expanded.toggle() }.font(.subheadline)
                        }.listRowBackground(MidokuTheme.surface)
                    }
                    if let error = entry.links.compactMap({ state.listing($0.listingID)?.lastError }).first {
                        Section { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(MidokuTheme.secondaryText) }.listRowBackground(MidokuTheme.surface)
                    }
                    if let message { Section { Text(message).font(.caption) }.listRowBackground(MidokuTheme.surface) }
                    Section {
                        HStack {
                            Text("\(entry.slots.count) chapters").font(.subheadline.weight(.semibold))
                            Spacer()
                            filters(entry)
                            NavigationLink { ClipboardView() } label: { Label("Chapter clipboard", systemImage: "doc.on.clipboard").labelStyle(.iconOnly).frame(width: 44, height: 44) }.buttonStyle(.plain)
                            Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }
                        }
                        if entry.slots.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your next read starts here").font(.headline)
                                Text("Copy chapters from Browse, then paste them into this entry.").font(.callout).foregroundStyle(MidokuTheme.secondaryText)
                                Button("Paste from clipboard") { pasting = true }.disabled(state.clipboard.isEmpty)
                                NavigationLink("Find chapters") { SourceDirectoryView(extensions: extensions) }
                            }.padding(.vertical, 8)
                        }
                        ForEach(visibleSlots(entry)) { slot in chapterRow(slot, entry: entry) }
                        if !entry.slots.isEmpty && visibleSlots(entry).isEmpty { Text("No chapters match these filters.").foregroundStyle(MidokuTheme.secondaryText) }
                    } footer: { Text(entry.manualOrder ? "Manual reading order. New followed chapters append at the end." : "Reading order follows chapter numbers. Display filters and reverse sorting do not change Next Chapter.") }.listRowBackground(MidokuTheme.surface)
                }.settingsStyle().refreshable { await library.refresh(entryIDs: [entryID]) }
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
                    Button("Paste chapters (\(state.clipboard.count))", systemImage: "doc.on.clipboard") { pasting = true }.disabled(state.clipboard.isEmpty)
                    NavigationLink { RemovedChaptersView(entryID: entryID) } label: { Label("Removed chapters", systemImage: "arrow.uturn.backward") }
                    Button("Restore automatic reading order", systemImage: "arrow.up.arrow.down") { change { try $0.library.editEntry(entryID) { $0.manualOrder = false } } }
                    Button("Remove from library", systemImage: "trash", role: .destructive) { removing = true }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Entry actions") }.disabled(entry == nil)
            }.sharedBackgroundVisibility(.hidden)
        }
        #if DEBUG
        .onAppear {
            if CommandLine.arguments.contains("--rename-preview"), renamedSlot == nil { renamedSlot = entry?.slots.first }
        }
        #endif
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                LibraryCoverView(entry: entry, extensions: extensions).frame(width: 96, height: 138).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.title(entry)).font(.title3.bold()).textSelection(.enabled)
                    let metadata = state.listing(entry.primaryListingID)?.details
                    if let authors = entry.authorOverride ?? metadata?.authors?.joined(separator: ", "), !authors.isEmpty { Text(authors).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                    Text([entry.status.title, metadata?.status?.capitalized].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                    Text("\(entry.slots.filter { !state.isRead($0) }.count) unread").font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                    let categories = settings.snapshot.categories.filter { entry.categoryIDs.contains($0.id) }.map(\.name)
                    if !categories.isEmpty { Text(categories.joined(separator: " · ")).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let slot = state.resumeSlot(entry, positions: settings.snapshot.progress) {
                NavigationLink { LibraryReaderView(entryID: entryID, initialSlotID: slot, extensions: extensions) } label: {
                    Label(entry.lastReadAt == nil ? "Start reading" : "Continue reading", systemImage: "book.pages").frame(maxWidth: .infinity)
                }.buttonStyle(MidokuPrimaryButtonStyle())
            }
        }.padding(.vertical, 4)
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
        } label: { Label("Filters", systemImage: "line.3.horizontal.decrease") }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
    }
    @ViewBuilder private func chapterRow(_ slot: ChapterSlot, entry: PersonalEntry) -> some View {
        if let variant = slot.preferred, let chapter = state.chapter(variant.chapterID) {
            HStack(spacing: 8) {
                if selecting { Button { toggle(slot.id) } label: { rowLabel(slot, variant: variant, chapter: chapter, entry: entry) }.buttonStyle(.plain) }
                else { NavigationLink { LibraryReaderView(entryID: entryID, initialSlotID: slot.id, extensions: extensions) } label: { rowLabel(slot, variant: variant, chapter: chapter, entry: entry) } }
                Menu {
                    Button("Copy chapter", systemImage: "doc.on.doc") { copy([slot.id]) }
                    Button("Rename chapter", systemImage: "character.cursor.ibeam") { renamedSlot = slot }
                    Button("Edit chapter", systemImage: "pencil") { editedSlot = slot }
                    Button(state.isRead(slot) ? "Mark unread" : "Mark read", systemImage: "checkmark.circle") { let read = !state.isRead(slot); change { try $0.markSlots(entryID: entryID, slots: [slot.id], read: read) } }
                    Button("Download", systemImage: "arrow.down.circle") { download([slot.id]) }
                    Button("Alternatives (\(slot.variants.count))", systemImage: "square.stack") { alternatives = slot }
                    Button("Move earlier", systemImage: "arrow.up") { change { try $0.library.moveSlot(entryID: entryID, slotID: slot.id, offset: -1) } }.disabled(entry.slots.first?.id == slot.id)
                    Button("Move later", systemImage: "arrow.down") { change { try $0.library.moveSlot(entryID: entryID, slotID: slot.id, offset: 1) } }.disabled(entry.slots.last?.id == slot.id)
                    if let url = state.listings.first(where: { $0.identity == chapter.identity.listing })?.details.webURL { Link("Open original listing", destination: url) }
                    Button("Select", systemImage: "checkmark.circle") { selecting = true; selected.insert(slot.id) }
                    Button("Remove from this entry", systemImage: "trash", role: .destructive) { selected = [slot.id]; deleteChapters = true }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Chapter actions")
            }.contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { copy([slot.id]) }
                Button("Select", systemImage: "checkmark.circle") { selecting = true; selected.insert(slot.id) }
                Button("Rename chapter", systemImage: "character.cursor.ibeam") { renamedSlot = slot }
                Button("Edit", systemImage: "pencil") { editedSlot = slot }
            }
        }
    }
    private func rowLabel(_ slot: ChapterSlot, variant: ChapterVariant, chapter: LibraryChapter, entry: PersonalEntry) -> some View {
        HStack(spacing: 12) {
            if selecting { Image(systemName: selected.contains(slot.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
            if settings.snapshot.preferences.chapterThumbnails { ChapterCoverView(identity: chapter.identity, extensions: extensions, overrideID: variant.edits.coverID).frame(width: 72, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 6)) }
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
