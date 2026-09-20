import AidokuRunner
import SwiftUI

struct MCAddChapterToEntryView: View {
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    @State private var store = MCCollectionStore.shared
    @State private var chapterName = ""
    @State private var query = ""
    @State private var selectedEntryID: UUID?
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    private var entries: [MCPersonalEntry] {
        store.library.entries
            .filter { query.isEmpty || store.library.title($0).localizedCaseInsensitiveContains(query) }
            .sorted { store.library.title($0).localizedStandardCompare(store.library.title($1)) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chapter") {
                    TextField("Chapter name", text: $chapterName)
                }

                Section("Library entry") {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "Library empty" : "No entries found",
                            systemImage: "books.vertical",
                            description: Text(query.isEmpty ? "Save an entry to the Library first." : "Try another search.")
                        )
                    } else {
                        ForEach(entries) { entry in
                            Button {
                                selectedEntryID = entry.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(store.library.title(entry)).foregroundStyle(.primary).lineLimit(2)
                                        Text("\(entry.slots.count) chapters · \(entry.status.title)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedEntryID == entry.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search library")
            .navigationTitle("Add to entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(selectedEntryID == nil || chapterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                chapterName = chapter.formattedTitle()
                selectedEntryID = store.entryID(for: manga)
            }
            .mcErrors(store)
        }
        .midokuAccent()
    }

    private func add() {
        guard let selectedEntryID else { return }
        do {
            try store.addChapter(chapter, from: manga, to: selectedEntryID, title: chapterName)
            dismiss()
        } catch {
            store.error = error.localizedDescription
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
    @State private var openEntry: MCID?
    var body: some View {
        Menu {
            if let id = store.entryID(for: manga) {
                Button("Open library entry", systemImage: "books.vertical") { openEntry = MCID(id: id) }
            } else {
                Button("Add to library", systemImage: "plus") { add = true }
            }
        } label: { Image(systemName: "books.vertical") }
            .accessibilityLabel("Library actions")
            .sheet(isPresented: $add) { MCAddSourceView(manga: manga, chapters: chapters) }
            .sheet(item: $openEntry) { item in NavigationStack { MCEntryView(entryID: item.id) } }
            .mcErrors(store)
    }
}
