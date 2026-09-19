import SwiftUI

struct AddSourceEntryView: View {
    let adapter: any SourceAdapter
    let mangaID: String
    let title: String
    let language: String?
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var categories: Set<UUID> = []
    @State private var working = false
    @State private var error: String?
    @State private var addedID: UUID?
    @State private var destination: PersonalEntry?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title).font(.headline)
                    Text("All pages of the chapter list are loaded before saving. This entry will follow new chapters in \(language ?? "all available languages").").font(.callout).foregroundStyle(MidokuTheme.secondaryText)
                    if working { ProgressView("Loading complete chapter list…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    if let addedID {
                        Label("Saved to your library", systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
                        NavigationLink("Open library entry") { LibraryEntryView(entryID: addedID, extensions: extensions) }
                    } else { Button("Add as a new entry", systemImage: "plus") { add() }.disabled(working) }
                }
                if addedID == nil {
                    Section("Categories") {
                        if settings.snapshot.categories.isEmpty { Text("New entries appear in Uncategorized.").foregroundStyle(MidokuTheme.secondaryText) }
                        ForEach(settings.snapshot.categories) { category in Toggle(category.name, isOn: Binding(get: { categories.contains(category.id) }, set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } })) }
                    }
                    if !settings.snapshot.library.entries.isEmpty {
                        Section {
                            ForEach(settings.snapshot.library.entries) { entry in
                                Button(settings.snapshot.library.title(entry)) { preparePaste(entry) }.disabled(working)
                            }
                        } header: { Text("Or review chapters for an existing entry") } footer: { Text("Choose a destination to review duplicates and chapter order before linking the selected releases.") }
                    }
                }
            }.settingsStyle().navigationTitle("Add to library")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) }.sharedBackgroundVisibility(.hidden) }
        }.interactiveDismissDisabled(working)
        .sheet(item: $destination) { entry in PasteReviewView(entryID: entry.id) }
    }
    private func add() {
        working = true
        Task {
            do { addedID = try await library.add(adapter: adapter, mangaID: mangaID, language: language, categories: categories) }
            catch { self.error = error.localizedDescription }
            working = false
        }
    }
    private func preparePaste(_ entry: PersonalEntry) {
        working = true
        Task {
            do {
                let result = try await library.fullSnapshot(adapter: adapter, mangaID: mangaID, language: language)
                try await library.copy(details: result.0, connection: adapter.connection, chapters: result.1)
                destination = entry
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

struct EntrySourcesView: View {
    let entryID: UUID
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var following: EntrySourceLink?
    @State private var error: String?
    @State private var working = false
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if working { ProgressView("Checking source chapters…") }
                if let entry = settings.snapshot.library.entry(entryID) {
                    if entry.links.isEmpty { Text("Copy chapters from Browse and paste them here to link a source.") }
                    ForEach(entry.links) { link in
                        if let listing = settings.snapshot.library.listing(link.listingID) {
                            Section {
                                Text(listing.details.title).font(.headline)
                                Text(settings.snapshot.connections.first { $0.id == listing.identity.connectionID }?.name ?? "Unavailable source").font(.subheadline)
                                Text(link.followsNewChapters ? "Following new chapters" : "Selected chapters only").foregroundStyle(.tint)
                                if let language = link.language { LabeledContent("Language", value: language) }
                                if let date = listing.refreshedAt { LabeledContent("Last refreshed", value: date.formatted(date: .abbreviated, time: .shortened)) }
                                if let error = listing.lastError { Text(error).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                                if entry.primaryListingID == listing.id { Label("Metadata source", systemImage: "checkmark.circle") }
                                else { Button("Use for inherited details and cover") { change { try $0.library.editEntry(entryID) { $0.primaryListingID = listing.id } } } }
                                if link.followsNewChapters {
                                    Button("Stop following new chapters") { change { try $0.library.editEntry(entryID) { entry in if let index = entry.links.firstIndex(where: { $0.id == link.id }) { entry.links[index].followsNewChapters = false } } } }
                                } else { Button("Follow future chapters") { following = link }.disabled(working) }
                                if let url = listing.details.webURL { Link("Open original listing", destination: url) }
                            } footer: { Text("Local title, description, author and cover edits are preserved. Chapter references remain available when following is off.") }
                        }
                    }
                }
            }.settingsStyle().navigationTitle("Entry sources")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) }.sharedBackgroundVisibility(.hidden) }
        }.interactiveDismissDisabled(working)
        .confirmationDialog("Follow only future chapters?", isPresented: Binding(get: { following != nil }, set: { if !$0 { following = nil } }), titleVisibility: .visible) {
            if let link = following { Button("Follow future chapters") { follow(link) } }
        } message: { Text("We’ll check the complete list now and keep your current selection. Only chapters first discovered afterward will be added. Existing chapters can still be copied and pasted with review.") }
    }
    private func change(_ edit: @escaping (inout AppSnapshot) throws -> Void) { Task { do { try await settings.commit(edit) } catch { self.error = error.localizedDescription } } }
    private func follow(_ link: EntrySourceLink) {
        guard let listing = settings.snapshot.library.listing(link.listingID), let connection = settings.snapshot.connections.first(where: { $0.id == listing.identity.connectionID }) else { error = LibraryFailure.missing.localizedDescription; return }
        working = true
        Task {
            do {
                let adapter = try await extensions.adapter(for: connection)
                let result = try await library.fullSnapshot(adapter: adapter, mangaID: listing.identity.externalID, language: link.language)
                try await settings.commit { state in
                    _ = try state.library.remember(details: result.0, connectionID: connection.id, records: result.1, complete: true, language: link.language)
                    let baseline = Set(state.library.chapters.filter { $0.identity.listing == listing.identity }.map(\.id))
                    try state.library.editEntry(entryID) { entry in
                        guard let index = entry.links.firstIndex(where: { $0.id == link.id }) else { throw LibraryFailure.stalePreview }
                        entry.links[index].followsNewChapters = true; entry.links[index].followBaseline = baseline
                    }
                }
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}
