import AidokuRunner
import SwiftUI

struct MCEntryView: View {
    let entryID: UUID
    @State private var store = MCCollectionStore.shared
    @State private var showEdit = false
    @State private var showPaste = false
    @State private var showSources = false
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var editingChapter: MCID?
    @State private var reader: MCReaderSheet?
    @State private var query = ""
    @State private var editingOrder = false
    @AppStorage("Midoku.chapterGrid") private var grid = false
    private var entry: MCPersonalEntry? { store.library.entry(entryID) }
    private var slots: [MCChapterSlot] {
        guard let entry else { return [] }
        let values = entry.slots.filter { slot in query.isEmpty || slot.preferred.map { store.library.chapterDisplayTitle($0).localizedCaseInsensitiveContains(query) } == true }
        return entry.descendingDisplay && !editingOrder ? Array(values.reversed()) : values
    }

    var body: some View {
        Group {
            if let entry {
                List {
                    header(entry).listRowSeparator(.hidden)
                    HStack {
                        Text("\(entry.slots.count) chapters").font(.headline)
                        Spacer()
                        if store.isRefreshing { ProgressView() }
                        Button { selecting.toggle(); selected.removeAll() } label: { Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle") }
                            .accessibilityLabel(selecting ? "Done selecting" : "Select chapters")
                        Button { store.perform { try $0.library.editEntry(entryID) { $0.descendingDisplay.toggle() } } } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Reverse displayed chapter order")
                    }.buttonStyle(.borderless)
                    if slots.isEmpty { Text("Copy chapters from a source, then paste them here.").foregroundStyle(.secondary) }
                    if grid && !editingOrder {
                        ForEach(stride(from: 0, to: slots.count, by: 3).map { $0 }, id: \.self) { offset in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(slots[offset..<min(offset + 3, slots.count)])) { slot in
                                    chapterRow(slot, grid: true).frame(maxWidth: .infinity)
                                }
                                ForEach(0..<max(0, 3 - min(3, slots.count - offset)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                            }.listRowSeparator(.hidden)
                        }
                    } else {
                        ForEach(slots) { chapterRow($0, grid: false) }
                            .onMove { from, to in
                                guard query.isEmpty else { return }
                                store.perform { state in
                                    try state.library.editEntry(entryID) { entry in entry.manualOrder = true; entry.slots.move(fromOffsets: from, toOffset: to) }
                                }
                            }
                            .onDelete { indices in
                                let ids = Set(indices.map { slots[$0].id })
                                store.perform { try $0.library.removeSlots(entryID: entryID, slotIDs: ids) }
                            }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).background(Color("MidokuBackground"))
                .environment(\.editMode, .constant(editingOrder ? .active : .inactive))
                .refreshable { await store.refresh(entryID: entryID) }
                .navigationTitle(store.library.title(entry)).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search chapters")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit entry", systemImage: "square.and.pencil") { showEdit = true }
                            if !store.library.clipboard.isEmpty { Button("Paste \(store.library.clipboard.count) chapters", systemImage: "doc.on.clipboard") { showPaste = true } }
                            Button("Sources and alternatives", systemImage: "square.stack.3d.up") { showSources = true }
                            Toggle("Chapter grid", isOn: $grid)
                            Button(editingOrder ? "Finish ordering" : "Reorder chapters", systemImage: "line.3.horizontal") { query = ""; editingOrder.toggle() }
                            if entry.manualOrder {
                                Button("Restore chapter-number order") { store.perform { try $0.library.editEntry(entryID) { $0.manualOrder = false } } }
                            }
                            Button("Refresh sources", systemImage: "arrow.clockwise") { Task { await store.refresh(entryID: entryID) } }.disabled(store.isRefreshing)
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Entry options")
                    }
                    if selecting {
                        ToolbarItem(placement: .bottomBar) {
                            Menu("\(selected.count) selected") {
                                Button("Select all") { selected = Set(slots.map(\.id)) }
                                Button("Copy chapters", systemImage: "doc.on.doc") { copySelected(); selecting = false }
                                Button("Mark read") { store.setRead(entryID: entryID, slotIDs: selected, read: true) }
                                Button("Mark unread") { store.setRead(entryID: entryID, slotIDs: selected, read: false) }
                                Button("Remove from entry", role: .destructive) {
                                    if store.perform({ try $0.library.removeSlots(entryID: entryID, slotIDs: selected) }) { selected.removeAll(); selecting = false }
                                }
                            }
                        }
                    }
                }
            } else { ContentUnavailableView("Entry unavailable", systemImage: "book.closed") }
        }
        .sheet(isPresented: $showEdit) { MCEntryEditor(entryID: entryID) }
        .sheet(isPresented: $showPaste) { MCPasteView(entryID: entryID) }
        .sheet(isPresented: $showSources) { MCEntrySourcesView(entryID: entryID) }
        .sheet(item: $editingChapter) { MCChapterEditor(entryID: entryID, slotID: $0.id) }
        .fullScreenCover(item: $reader) { MCReaderView(sequence: $0.sequence).ignoresSafeArea() }
        .mcErrors(store)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--edit-preview") { showEdit = true }
            if ProcessInfo.processInfo.arguments.contains("--paste-preview") { showPaste = true }
            #endif
        }
    }

    private func header(_ entry: MCPersonalEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                MCEntryCover(entry: entry).frame(width: 88, height: 132).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.library.title(entry)).font(.title3.bold()).lineLimit(3)
                    Text(entry.authorOverride ?? store.library.listing(entry.primaryListingID)?.details.authors?.joined(separator: ", ") ?? "").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(entry.status.title) · \(entry.links.count) sources").font(.caption).foregroundStyle(.secondary)
                    Button {
                        let slot = entry.slots.first { !store.library.isRead($0) } ?? entry.slots.first
                        if let slot { open(slot) }
                    } label: { Label("Read", systemImage: "book.fill").frame(minWidth: 80) }.buttonStyle(.borderedProminent).disabled(entry.slots.isEmpty)
                }
            }
            if !store.library.description(entry).isEmpty {
                Text(store.library.description(entry)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            if !store.library.clipboard.isEmpty {
                Button("Paste \(store.library.clipboard.count) copied chapters", systemImage: "doc.on.clipboard") { showPaste = true }.font(.subheadline)
            }
        }.padding(.vertical, 4)
    }

    private func chapterRow(_ slot: MCChapterSlot, grid: Bool) -> some View {
        Button {
            if selecting { if !selected.insert(slot.id).inserted { selected.remove(slot.id) } }
            else { open(slot) }
        } label: {
            Group {
                if grid {
                    VStack(alignment: .leading, spacing: 6) {
                        MCChapterThumbnail(variant: slot.preferred).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 7))
                        chapterText(slot, compact: true)
                    }
                } else {
                    HStack(spacing: 12) {
                        MCChapterThumbnail(variant: slot.preferred).frame(width: 48, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
                        chapterText(slot, compact: false)
                        Spacer(minLength: 0)
                        if selecting { Image(systemName: selected.contains(slot.id) ? "checkmark.circle.fill" : "circle") }
                        else if store.library.isRead(slot) { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.contentShape(Rectangle()).opacity(store.library.isRead(slot) ? 0.65 : 1)
        }.buttonStyle(.plain)
            .contextMenu {
                Button("Read chapter", systemImage: "book") { open(slot) }
                Button("Edit chapter", systemImage: "pencil") { editingChapter = MCID(id: slot.id) }
                Button("Copy chapter", systemImage: "doc.on.doc") {
                    guard let variant = slot.preferred else { return }
                    store.perform { try $0.library.copy([MCCopiedChapter(chapterID: variant.chapterID, edits: variant.edits)]) }
                }
                Button(store.library.isRead(slot) ? "Mark unread" : "Mark read") { store.setRead(entryID: entryID, slotIDs: [slot.id], read: !store.library.isRead(slot)) }
                Button("Download", systemImage: "arrow.down.circle") {
                    guard let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID), let physical = store.physical(chapter.identity) else { return }
                    Task { await DownloadManager.shared.download(manga: physical.manga, chapters: [physical.chapter]) }
                }
                if slot.variants.count > 1 {
                    Menu("Preferred source") {
                        ForEach(slot.variants) { variant in
                            let origin = store.library.chapter(variant.chapterID)
                            Button(origin.map { store.sourceName($0.identity.listing.connectionID) } ?? "Unavailable") {
                                store.perform { state in try state.library.editEntry(entryID) { entry in
                                    guard let i = entry.slots.firstIndex(where: { $0.id == slot.id }) else { throw MCLibraryFailure.missing }
                                    entry.slots[i].preferredID = variant.id; entry.slots[i].completionOverride = nil
                                } }
                            }
                        }
                    }
                }
                Button("Remove from entry", role: .destructive) { store.perform { try $0.library.removeSlots(entryID: entryID, slotIDs: [slot.id]) } }
            }
    }

    private func chapterText(_ slot: MCChapterSlot, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let variant = slot.preferred, let chapter = store.library.chapter(variant.chapterID) {
                Text(store.library.chapterDisplayTitle(variant)).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.medium)).lineLimit(1)
                if !chapter.record.title.isEmpty && chapter.record.title != store.library.chapterDisplayTitle(variant) {
                    Text(chapter.record.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(store.sourceName(chapter.identity.listing.connectionID)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if slot.variants.count > 1 { Text("\(slot.variants.count) alternatives").font(.caption2).foregroundStyle(.tint) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ slot: MCChapterSlot) {
        do { reader = MCReaderSheet(sequence: try MCReaderSequence(entryID: entryID, slotID: slot.id)) }
        catch { store.error = error.localizedDescription }
    }
    private func copySelected() {
        let items = entry?.slots.filter { selected.contains($0.id) }.compactMap(\.preferred).map { MCCopiedChapter(chapterID: $0.chapterID, edits: $0.edits) } ?? []
        store.perform { try $0.library.copy(items) }
    }
}
