import AidokuRunner
import PhotosUI
import SwiftUI

struct MCPasteView: View {
    let entryID: UUID
    @State private var store = MCCollectionStore.shared
    @State private var choices: [MCPasteChoice] = []
    @State private var revision = 0
    @State private var loaded = false
    @State private var covers: [MCLibraryCover] = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let entry = store.library.entry(entryID) {
                    Section { Text("Paste into \(store.library.title(entry))").font(.headline) }
                    ForEach($choices) { $choice in
                        Section {
                            if let chapter = store.library.chapter(choice.item.chapterID) {
                                Text(store.library.chapterDisplayTitle(MCChapterVariant(chapterID: chapter.id, edits: choice.item.edits))).font(.headline)
                                Text(store.sourceName(chapter.identity.listing.connectionID)).font(.caption).foregroundStyle(.secondary)
                                MCChapterDraftFields(chapter: chapter, edits: $choice.item.edits, covers: $covers)
                                .onChange(of: choice.item.edits.number) { _, _ in
                                    if let updated = try? store.library.pastePreview(entryID: entryID, items: [choice.item]).first {
                                        choice.targetSlotID = updated.targetSlotID
                                        choice.action = updated.action
                                    }
                                }
                                Picker("Action", selection: $choice.action) {
                                    Text("Choose…").tag(MCPasteAction.unresolved)
                                    Text("Skip").tag(MCPasteAction.skip)
                                    Text("Keep separate").tag(MCPasteAction.separate)
                                    if choice.targetSlotID != nil {
                                        Text("Keep as alternative").tag(MCPasteAction.alternative)
                                        Text("Replace existing").tag(MCPasteAction.replace)
                                    }
                                }
                                if choice.action == .replace { Toggle("Keep completed state", isOn: $choice.preserveCompletion) }
                                if entry.exclusions.contains(chapter.id) { Toggle("Restore previously removed chapter", isOn: $choice.restoreExcluded) }
                            }
                        }
                    }
                }
            }.navigationTitle("Review chapters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Paste") {
                        if store.perform({ state in
                            let used = Set(choices.filter { $0.action != .skip }.compactMap { $0.item.edits.coverID })
                            state.library.covers.append(contentsOf: covers.filter { used.contains($0.id) })
                            try state.library.paste(entryID: entryID, revision: revision, choices: choices)
                        }) { dismiss() }
                    }.disabled(choices.isEmpty || choices.contains { $0.action == .unresolved }) }
                }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    do { choices = try store.library.pastePreview(entryID: entryID); revision = store.library.entry(entryID)?.sequenceRevision ?? 0 }
                    catch { store.error = error.localizedDescription }
                }.mcErrors(store)
        }
    }
}

private struct MCChapterDraftFields: View {
    let chapter: MCLibraryChapter
    @Binding var edits: MCChapterEdits
    @Binding var covers: [MCLibraryCover]
    @State private var photo: PhotosPickerItem?
    @State private var store = MCCollectionStore.shared
    private var variant: MCChapterVariant { MCChapterVariant(chapterID: chapter.id, edits: edits) }
    var body: some View {
        LabeledContent("Title") { TextField("Title", text: Binding(get: { edits.title ?? store.library.chapterDisplayTitle(variant) }, set: { edits.title = $0 })).multilineTextAlignment(.trailing) }
        LabeledContent("Number") { TextField("Number", text: Binding(get: { edits.number ?? chapter.record.number ?? "" }, set: { edits.number = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
        LabeledContent("Volume") { TextField("Volume", text: Binding(get: { edits.volume ?? chapter.record.volume ?? "" }, set: { edits.volume = $0 })).multilineTextAlignment(.trailing) }
        PhotosPicker("Choose thumbnail", selection: $photo, matching: .images)
            .onChange(of: photo) { _, value in Task {
                do {
                    if let data = try await value?.loadTransferable(type: Data.self) {
                        let cover = try store.saveCover(data: data)
                        covers.append(cover); edits.coverID = cover.id
                    }
                } catch { store.error = error.localizedDescription }
            } }
        if let id = edits.coverID, let cover = (covers + store.library.covers).first(where: { $0.id == id }), let image = UIImage(data: cover.data) {
            Image(uiImage: image).resizable().scaledToFit().frame(height: 120)
        }
        Button("Reset edits") { edits = MCChapterEdits() }
    }
}

struct MCEntrySourcesView: View {
    let entryID: UUID
    @State private var store = MCCollectionStore.shared
    @State private var listing: MCID?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let entry = store.library.entry(entryID) {
                    ForEach(entry.links) { link in
                        if let record = store.library.listing(link.listingID) {
                            Section(store.sourceName(record.identity.connectionID)) {
                                Text(record.details.title)
                                Button("Open original listing", systemImage: "arrow.up.forward.app") { listing = MCID(id: record.id) }
                                Toggle("Follow new chapters", isOn: Binding(get: { link.followsNewChapters }, set: { value in
                                    store.perform { state in
                                        let baseline = Set(state.library.chapters.filter { $0.identity.listing == record.identity }.map(\.id))
                                        try state.library.editEntry(entryID) { entry in
                                            guard let i = entry.links.firstIndex(where: { $0.id == link.id }) else { throw MCLibraryFailure.missing }
                                            entry.links[i].followsNewChapters = value
                                            if value { entry.links[i].followBaseline = baseline }
                                        }
                                    }
                                }))
                                if entry.primaryListingID != record.id {
                                    Button("Use source details") { store.perform { try $0.library.editEntry(entryID) { $0.primaryListingID = record.id } } }
                                }
                            }
                        }
                    }
                    let alternatives = entry.slots.filter { $0.variants.count > 1 }
                    ForEach(alternatives) { slot in
                        Section(slot.preferred.map { store.library.chapterDisplayTitle($0) } ?? "Chapter") {
                            ForEach(slot.variants) { variant in
                                if let chapter = store.library.chapter(variant.chapterID) {
                                    Button {
                                        store.perform { state in try state.library.editEntry(entryID) { entry in
                                            guard let i = entry.slots.firstIndex(where: { $0.id == slot.id }) else { throw MCLibraryFailure.missing }
                                            entry.slots[i].preferredID = variant.id; entry.slots[i].completionOverride = nil
                                        } }
                                    } label: {
                                        HStack { Text(store.sourceName(chapter.identity.listing.connectionID)); Spacer(); if variant.id == slot.preferredID { Image(systemName: "checkmark") } }
                                    }
                                }
                            }
                        }
                    }
                    if !entry.exclusions.isEmpty {
                        Section("Removed chapters") {
                            ForEach(store.library.chapters.filter { entry.exclusions.contains($0.id) }) { chapter in
                                Button {
                                    store.perform { try $0.library.restoreChapter(entryID: entryID, chapterID: chapter.id) }
                                } label: {
                                    Label("Restore \(chapter.record.number.map { "Chapter \($0)" } ?? chapter.record.title) · \(store.sourceName(chapter.identity.listing.connectionID))", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("Sources and chapters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $listing) { item in
                    if let manga = store.snapshot.manga.first(where: { $0.listingID == item.id })?.manga { MCOriginalListingView(manga: manga) }
                }.mcErrors(store)
        }
    }
}

struct MCOriginalListingView: UIViewControllerRepresentable {
    let manga: AidokuRunner.Manga
    func makeUIViewController(context: Context) -> UINavigationController {
        let nav = NavigationController()
        let page = MangaViewController(manga: manga, parent: nav)
        nav.setViewControllers([page], animated: false)
        return nav
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct MCSourceActions: View {
    let manga: AidokuRunner.Manga
    let chapters: [AidokuRunner.Chapter]
    let selected: Set<String>
    @State private var store = MCCollectionStore.shared
    @State private var add = false
    @State private var copied = false
    @State private var openEntry: MCID?
    var body: some View {
        Menu {
            if let id = store.entryID(for: manga) {
                Button("Open collection entry", systemImage: "books.vertical") { openEntry = MCID(id: id) }
            } else {
                Button("Add to collection", systemImage: "plus") { add = true }
            }
            Button(selected.isEmpty ? "Copy all chapters" : "Copy \(selected.count) selected chapters", systemImage: "doc.on.doc") {
                store.copy(manga: manga, chapters: selected.isEmpty ? chapters : chapters.filter { selected.contains($0.key) })
                copied = store.error == nil
            }.disabled(chapters.isEmpty)
        } label: { Image(systemName: "books.vertical") }
            .accessibilityLabel("Collection actions")
            .sheet(isPresented: $add) { MCAddSourceView(manga: manga, chapters: chapters) }
            .sheet(item: $openEntry) { item in NavigationStack { MCEntryView(entryID: item.id) } }
            .alert("Chapters copied", isPresented: $copied) { Button("OK") {} } message: { Text("Open a collection entry and choose Paste chapters.") }
            .mcErrors(store)
    }
}
