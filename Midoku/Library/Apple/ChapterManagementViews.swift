import SwiftUI

struct ClipboardView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var destination: PersonalEntry?
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                if settings.snapshot.library.clipboard.isEmpty { Text("Copy chapters from Browse or a library entry to get started.") }
                ForEach(settings.snapshot.library.clipboard) { item in
                    if let chapter = settings.snapshot.library.chapter(item.chapterID) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.edits.title ?? chapter.record.title)
                            Text(sourceName(chapter, settings: settings)).font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                        }
                    }
                }.onDelete { offsets in
                    let ids = Set(offsets.map { settings.snapshot.library.clipboard[$0].chapterID })
                    Task { do { try await settings.commit { $0.library.clipboard.removeAll { ids.contains($0.chapterID) } } } catch { self.error = error.localizedDescription } }
                }
            } header: { Text("\(settings.snapshot.library.clipboard.count) copied chapters") }
            if !settings.snapshot.library.clipboard.isEmpty {
                Section("Paste into") {
                    ForEach(settings.snapshot.library.entries) { entry in
                        Button(settings.snapshot.library.title(entry)) { destination = entry }
                    }
                    if settings.snapshot.library.entries.isEmpty { Text("Create an entry in Library before pasting.") }
                }
            }
        }.settingsStyle().navigationTitle("Chapter clipboard")
        .toolbar { Button("Clear") { Task { do { try await settings.commit { $0.library.clipboard = [] } } catch { self.error = error.localizedDescription } } }.disabled(settings.snapshot.library.clipboard.isEmpty) }
        .sheet(item: $destination) { entry in PasteReviewView(entryID: entry.id) }
    }
}

struct PasteReviewView: View {
    let entryID: UUID
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [PasteChoice] = []
    @State private var revision: Int?
    @State private var before: UUID?
    @State private var error: String?
    @State private var saving = false
    private var state: LibraryState { settings.snapshot.library }
    private var entry: PersonalEntry? { state.entry(entryID) }
    var body: some View {
        NavigationStack {
            Form {
                if let entry {
                    Section {
                        Text(state.title(entry)).font(.headline)
                        Text("Only reviewed chapters are added. New source links keep this selection; they do not follow the whole series.").font(.callout).foregroundStyle(MidokuTheme.secondaryText)
                        Picker("Position", selection: $before) {
                            Text(entry.manualOrder ? "Append to reading order" : "Automatic chapter order").tag(UUID?.none)
                            ForEach(entry.slots) { slot in Text("Before \(slot.preferred.map { state.chapterTitle($0) } ?? "chapter")").tag(Optional(slot.id)) }
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    if choices.isEmpty { Text("The chapter clipboard is empty.") }
                    ForEach($choices) { $choice in
                        if let chapter = state.chapter(choice.item.chapterID) {
                            Section {
                                Text(choice.item.edits.title ?? chapter.record.title).font(.headline)
                                Text(sourceName(chapter, settings: settings)).font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                                if let listing = state.listings.first(where: { $0.identity == chapter.identity.listing }) { Text(listing.details.title).font(.caption) }
                                let existing = entry.slots.flatMap(\.variants).contains { $0.chapterID == chapter.id }
                                if existing { Label("Already added · will skip", systemImage: "checkmark.circle") }
                                else {
                                    Picker("Action", selection: $choice.action) {
                                        ForEach(PasteAction.allCases) { Text($0.title).tag($0) }
                                    }
                                    if choice.action == .unresolved { Text("This number may already exist. Confirm whether these releases are equivalent.").font(.caption).foregroundStyle(.orange) }
                                    if choice.action == .alternative || choice.action == .replace {
                                        Picker("Existing chapter", selection: $choice.targetSlotID) {
                                            Text("Choose chapter").tag(UUID?.none)
                                            ForEach(entry.slots) { slot in Text(slot.preferred.map { state.chapterTitle($0) } ?? "Chapter").tag(Optional(slot.id)) }
                                        }
                                        Text(choice.action == .alternative ? "The current preferred release stays selected. Change it in Alternatives." : "The old release will be excluded from refresh. Its page position and downloads stay with that release.").font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                                        if choice.action == .replace { Toggle("Keep logical completion if already read", isOn: $choice.preserveCompletion) }
                                    }
                                    if entry.exclusions.contains(chapter.id), choice.action != .skip { Toggle("Restore this removed chapter", isOn: $choice.restoreExcluded) }
                                }
                            }
                        }
                    }
                } else { Text("This entry is no longer available.") }
            }.settingsStyle().navigationTitle("Review chapters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Paste") { save() }.disabled(saving || !canSave) }
            }
        }.interactiveDismissDisabled(saving)
        .task {
            guard revision == nil else { return }
            do { choices = try state.pastePreview(entryID: entryID); revision = entry?.sequenceRevision } catch { self.error = error.localizedDescription }
        }
    }
    private var canSave: Bool {
        revision != nil && choices.contains { $0.action != .skip } && choices.allSatisfy { choice in
            choice.action != .unresolved && (!(choice.action == .alternative || choice.action == .replace) || choice.targetSlotID != nil) &&
            (choice.action == .skip || entry?.exclusions.contains(choice.id) != true || choice.restoreExcluded)
        }
    }
    private func save() {
        guard let revision else { return }; saving = true
        let reviewed = choices, position = before
        Task {
            do { try await settings.commit { try $0.library.paste(entryID: entryID, revision: revision, choices: reviewed, insertBefore: position) }; dismiss() }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

struct ChapterEditor: View {
    let entryID: UUID
    let slotID: UUID
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var variantID: UUID?
    @State private var edits = ChapterEdits()
    @State private var original: ChapterRecord?
    @State private var cover: Data?
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: Binding(get: { edits.title ?? original?.title ?? "" }, set: { edits.title = $0 }))
                    TextField("Chapter number", text: Binding(get: { edits.number ?? original?.number ?? "" }, set: { edits.number = $0 }))
                    TextField("Volume", text: Binding(get: { edits.volume ?? original?.volume ?? "" }, set: { edits.volume = $0 }))
                    Button("Use source fields") { edits.title = nil; edits.number = nil; edits.volume = nil }
                } footer: { Text("Edits apply to this release in this entry. The source reference and shared reading progress stay intact.") }
                Section("Chapter cover") {
                    CoverImportControls(data: $cover, error: $error)
                    Button("Use entry cover") { edits.coverID = nil; cover = nil }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.settingsStyle().navigationTitle("Edit chapter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(variantID == nil || saving) }
            }
        }.interactiveDismissDisabled(saving)
        .task {
            guard variantID == nil, let variant = settings.snapshot.library.entry(entryID)?.slots.first(where: { $0.id == slotID })?.preferred else { return }
            variantID = variant.id; edits = variant.edits; original = settings.snapshot.library.chapter(variant.chapterID)?.record
        }
    }
    private func save() {
        guard let variantID else { return }; saving = true
        var updated = edits
        Task {
            do {
                try await settings.commit { state in
                    if let cover { let asset = LibraryCover(data: cover); state.library.covers.append(asset); updated.coverID = asset.id }
                    try state.library.editEntry(entryID) { entry in
                        guard let slot = entry.slots.firstIndex(where: { $0.id == slotID }), let variant = entry.slots[slot].variants.firstIndex(where: { $0.id == variantID }) else { throw LibraryFailure.stalePreview }
                        entry.slots[slot].variants[variant].edits = updated
                    }
                }; dismiss()
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

struct AlternativesView: View {
    let entryID: UUID
    let slotID: UUID
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if let slot = settings.snapshot.library.entry(entryID)?.slots.first(where: { $0.id == slotID }) {
                    Section {
                        ForEach(slot.variants) { variant in
                            if let chapter = settings.snapshot.library.chapter(variant.chapterID) {
                                Button {
                                    Task { do { try await settings.commit { state in try state.library.editEntry(entryID) { entry in
                                        guard let index = entry.slots.firstIndex(where: { $0.id == slotID }), entry.slots[index].variants.contains(where: { $0.id == variant.id }) else { throw LibraryFailure.stalePreview }
                                        entry.slots[index].preferredID = variant.id; entry.slots[index].completionOverride = nil
                                    } } } catch { self.error = error.localizedDescription } }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(settings.snapshot.library.chapterTitle(variant))
                                            Text(sourceName(chapter, settings: settings)).font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                                            Text(settings.snapshot.library.completed.contains(chapter.identity) ? "Read" : "Unread").font(.caption)
                                        }
                                        Spacer()
                                        if slot.preferredID == variant.id { Image(systemName: "checkmark").accessibilityLabel("Preferred") }
                                    }
                                }
                            }
                        }
                    } footer: { Text("Choose the release used by Continue and Next Chapter. Page positions belong to each release and are never transferred.") }
                }
            }.settingsStyle().navigationTitle("Chapter alternatives")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RemovedChaptersView: View {
    let entryID: UUID
    @Environment(AppSettingsStore.self) private var settings
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            let removed = settings.snapshot.library.entry(entryID)?.exclusions ?? []
            if removed.isEmpty { Text("No chapters have been removed from this entry.") }
            ForEach(settings.snapshot.library.chapters.filter { removed.contains($0.id) }) { chapter in
                HStack {
                    VStack(alignment: .leading) { Text(chapter.record.title); Text(sourceName(chapter, settings: settings)).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                    Spacer()
                    Button("Restore") { Task { do { try await settings.commit { try $0.library.restoreChapter(entryID: entryID, chapterID: chapter.id) } } catch { self.error = error.localizedDescription } } }
                }
            }
        }.settingsStyle().navigationTitle("Removed chapters")
    }
}

private func sourceName(_ chapter: LibraryChapter, settings: AppSettingsStore) -> String {
    let name = settings.snapshot.connections.first { $0.id == chapter.identity.listing.connectionID }?.name ?? "Unavailable source"
    return ([name] + [chapter.record.language].compactMap { $0 } + (chapter.record.groups ?? [])).joined(separator: " · ")
}
