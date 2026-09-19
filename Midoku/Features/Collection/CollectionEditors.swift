import AidokuRunner
import PhotosUI
import SwiftUI

struct MCEntryEditor: View {
    let entryID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var title = ""
    @State private var author = ""
    @State private var summary = ""
    @State private var status = MCPersonalStatus.planned
    @State private var categories = Set<UUID>()
    @State private var photo: PhotosPickerItem?
    @State private var cover: MCLibraryCover?
    @State private var clearCover = false
    @State private var showCategories = false
    @State private var loaded = false
    @State private var resetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Description", text: $summary, axis: .vertical).lineLimit(4...12)
                    Picker("Reading status", selection: $status) { ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) } }
                }
                Section("Cover") {
                    if let cover, let image = UIImage(data: cover.data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 150) }
                    PhotosPicker("Choose cover", selection: $photo, matching: .images)
                    Toggle("Hide cover", isOn: $clearCover)
                }
                Section("Categories") {
                    ForEach(store.snapshot.categories) { item in
                        Toggle(item.name, isOn: Binding(get: { categories.contains(item.id) }, set: { if $0 { categories.insert(item.id) } else { categories.remove(item.id) } }))
                    }
                    Button("Manage categories") { showCategories = true }
                }
                if entryID != nil {
                    Section { Button("Reset to source details", role: .destructive) { resetConfirm = true } }
                }
            }
            .navigationTitle(entryID == nil ? "New entry" : "Edit entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let entryID, let entry = store.library.entry(entryID) {
                    title = store.library.title(entry); summary = store.library.description(entry)
                    author = entry.authorOverride ?? store.library.listing(entry.primaryListingID)?.details.authors?.joined(separator: ", ") ?? ""
                    status = entry.status; categories = entry.categoryIDs; clearCover = entry.hidesCover
                }
            }
            .onChange(of: photo) { _, photo in Task {
                do { if let data = try await photo?.loadTransferable(type: Data.self) { cover = try store.saveCover(data: data); clearCover = false } }
                catch { store.error = error.localizedDescription }
            } }
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .confirmationDialog("Reset this entry’s details?", isPresented: $resetConfirm) {
                Button("Reset details", role: .destructive) {
                    if let entryID, store.perform({ try $0.library.resetDetails(entryID) }) { dismiss() }
                }
            } message: { Text("Source chapters, mixed-source links, categories and progress are kept.") }
            .mcErrors(store)
        }
    }

    private func save() {
        if store.perform({ state in
            let id: UUID
            if let entryID { id = entryID } else { id = try state.library.createManual(title: title) }
            guard let original = state.library.entry(id) else { throw MCLibraryFailure.missing }
            let listing = state.library.listing(original.primaryListingID)
            if let cover { state.library.covers.append(cover) }
            let validCategories = categories.intersection(Set(state.categories.map(\.id)))
            try state.library.editEntry(id) { entry in
                if title != (original.titleOverride ?? listing?.details.title ?? "") || listing == nil { entry.titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                if summary != (original.descriptionOverride ?? listing?.details.description ?? "") { entry.descriptionOverride = summary }
                if author != (original.authorOverride ?? listing?.details.authors?.joined(separator: ", ") ?? "") { entry.authorOverride = author }
                entry.status = status; entry.categoryIDs = validCategories; entry.hidesCover = clearCover
                if let cover { entry.coverID = cover.id }
                if clearCover { entry.coverID = nil }
            }
        }) { dismiss() }
    }
}

struct MCChapterEditor: View {
    let entryID: UUID
    let slotID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var title = ""
    @State private var number = ""
    @State private var volume = ""
    @State private var cover: MCLibraryCover?
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false
    private var variant: MCChapterVariant? { store.library.entry(entryID)?.slots.first { $0.id == slotID }?.preferred }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Chapter title", text: $title)
                TextField("Chapter number", text: $number).keyboardType(.decimalPad)
                TextField("Volume", text: $volume)
                PhotosPicker("Choose chapter thumbnail", selection: $photo, matching: .images)
                if let cover, let image = UIImage(data: cover.data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 180) }
                Button("Reset chapter details") { save(reset: true) }
            }.navigationTitle("Edit chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(reset: false) } }
                }
                .onAppear {
                    guard !loaded, let variant else { return }; loaded = true
                    title = store.library.chapterTitle(variant); number = store.library.number(variant) ?? ""
                    volume = variant.edits.volume ?? store.library.chapter(variant.chapterID)?.record.volume ?? ""
                }
                .onChange(of: photo) { _, photo in Task {
                    do { if let data = try await photo?.loadTransferable(type: Data.self) { cover = try store.saveCover(data: data) } }
                    catch { store.error = error.localizedDescription }
                } }.mcErrors(store)
        }
    }
    private func save(reset: Bool) {
        guard let variant else { return }
        if store.perform({ state in
            if let cover, !reset { state.library.covers.append(cover) }
            try state.library.editEntry(entryID) { entry in
                guard let s = entry.slots.firstIndex(where: { $0.id == slotID }),
                      let v = entry.slots[s].variants.firstIndex(where: { $0.id == variant.id }) else { throw MCLibraryFailure.missing }
                if reset { entry.slots[s].variants[v].edits = MCChapterEdits() }
                else {
                    entry.slots[s].variants[v].edits.title = title
                    entry.slots[s].variants[v].edits.number = number
                    entry.slots[s].variants[v].edits.volume = volume
                    if let cover { entry.slots[s].variants[v].edits.coverID = cover.id }
                }
            }
        }) { dismiss() }
    }
}

struct MCCategoriesView: View {
    @State private var store = MCCollectionStore.shared
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Categories") {
                    ForEach(store.snapshot.categories) { category in
                        TextField("Category", text: Binding(get: { store.snapshot.categories.first { $0.id == category.id }?.name ?? category.name }, set: { value in
                            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            store.perform { state in if let i = state.categories.firstIndex(where: { $0.id == category.id }) { state.categories[i].name = String(value.prefix(80)) } }
                        }))
                    }.onDelete { indices in
                        let ids = Set(indices.map { store.snapshot.categories[$0].id })
                        store.perform { state in
                            state.categories.removeAll { ids.contains($0.id) }
                            for i in state.library.entries.indices { state.library.entries[i].categoryIDs.subtract(ids) }
                        }
                    }
                }
                Section {
                    TextField("New category", text: $name)
                    Button("Add category") {
                        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !store.snapshot.categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                        if store.perform({ $0.categories.append(MCCategory(name: String(value.prefix(80)))) }) { name = "" }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.navigationTitle("Categories").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.mcErrors(store)
        }
    }
}

struct MCAddSourceView: View {
    let manga: AidokuRunner.Manga
    let chapters: [AidokuRunner.Chapter]
    @State private var store = MCCollectionStore.shared
    @State private var categories = Set<UUID>()
    @State private var status = MCPersonalStatus.planned
    @State private var follow = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(manga.title).font(.headline)
                Picker("Reading status", selection: $status) { ForEach(MCPersonalStatus.allCases) { Text($0.title).tag($0) } }
                Toggle("Follow new chapters", isOn: $follow)
                Section("Categories") {
                    ForEach(store.snapshot.categories) { item in
                        Toggle(item.name, isOn: Binding(get: { categories.contains(item.id) }, set: { if $0 { categories.insert(item.id) } else { categories.remove(item.id) } }))
                    }
                    if store.snapshot.categories.isEmpty { Text("Create categories from Collection → Categories.").foregroundStyle(.secondary) }
                }
            }.navigationTitle("Add to collection").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") {
                        do {
                            _ = try store.add(manga, chapters: chapters, categories: categories, status: status, follow: follow)
                            Task { await MangaManager.shared.addToLibrary(manga: manga, chapters: chapters) }
                            dismiss()
                        } catch { store.error = error.localizedDescription }
                    } }
                }.mcErrors(store)
        }
    }
}
