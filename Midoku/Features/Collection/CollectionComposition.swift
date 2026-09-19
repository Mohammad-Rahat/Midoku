import AidokuRunner
import SwiftUI

struct MCPasteView: View {
    let entryID: UUID
    @State private var store = MCCollectionStore.shared
    @State private var choices: [MCPasteChoice] = []
    @State private var revision = 0
    @State private var loaded = false
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
                        if store.perform({ try $0.library.paste(entryID: entryID, revision: revision, choices: choices) }) { dismiss() }
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
