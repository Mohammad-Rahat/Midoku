import SwiftUI

struct CategoriesSettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var editing: LibraryCategory?
    @State private var name = ""
    @State private var showingEditor = false
    @State private var error: String?
    @State private var deleting: LibraryCategory?
    var body: some View {
        List {
            if settings.snapshot.categories.isEmpty {
                ContentUnavailableView("Make space for your favorites", systemImage: "folder.badge.plus",
                    description: Text("Create categories for your library, such as Reading or Weekend picks."))
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(settings.snapshot.categories) { category in
                    HStack {
                        Label(category.name, systemImage: "folder")
                        Spacer()
                        Menu {
                            Button("Rename", systemImage: "pencil") { edit(category) }
                            Button("Move up", systemImage: "arrow.up") { move(category.id, delta: -1) }
                                .disabled(settings.snapshot.categories.first?.id == category.id)
                            Button("Move down", systemImage: "arrow.down") { move(category.id, delta: 1) }
                                .disabled(settings.snapshot.categories.last?.id == category.id)
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = category }
                        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Manage \(category.name)")
                    }
                    .swipeActions { Button("Delete", role: .destructive) { deleting = category } }
                }
                .onMove { offsets, destination in settings.update { $0.categories.move(fromOffsets: offsets, toOffset: destination) } }
            } footer: {
                Text("Categories keep their order across launches. Deleting a category never deletes its manga. Assign entries from Library or Edit details.")
            }.listRowBackground(MidokuTheme.surface)
        }.settingsStyle().navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(settings.snapshot.categories.isEmpty) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { edit(nil) } label: { Label("Add category", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                NameEditor(title: editing == nil ? "New category" : "Rename category", name: name, limit: 80) { value in
                    try settings.saveCategory(id: editing?.id, name: value)
                }
            }
            .confirmationDialog("Delete category?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete category", role: .destructive) {
                    if let deleting { settings.deleteCategory(deleting.id) }
                    deleting = nil
                }
            } message: { Text("Only the category is removed. Your manga and reading progress are kept.") }
    }
    private func edit(_ category: LibraryCategory?) { editing = category; name = category?.name ?? ""; showingEditor = true }
    private func move(_ id: UUID, delta: Int) {
        settings.update { state in
            guard let index = state.categories.firstIndex(where: { $0.id == id }), state.categories.indices.contains(index + delta) else { return }
            state.categories.swapAt(index, index + delta)
        }
    }
}

struct NameEditor: View {
    let title: String
    @State var name: String
    let limit: Int
    let save: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).onSubmit { commit() }
                    if let error { Text(error).font(.footnote).foregroundStyle(MidokuTheme.danger) }
                } footer: { Text("Up to \(limit) characters.") }.listRowBackground(MidokuTheme.surface)
            }.settingsStyle().navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { commit() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > limit)
                    }
                }
        }.presentationDetents([.medium, .large])
    }
    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= limit else { error = SettingsFailure.emptyName.localizedDescription; return }
        do { try save(trimmed); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct HomeSectionsSettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var renaming: HomeSection?
    @State private var deleting: HomeSection?
    var body: some View {
        List {
            if settings.snapshot.homeSections.isEmpty {
                ContentUnavailableView("Your Home, in your order", systemImage: "pin",
                    description: Text("Open a source in Browse, choose a feed or search, then use Pin to Home. Your filters are saved with the section."))
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(settings.snapshot.homeSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title).font(.headline)
                                Text(section.sourceTitle).font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                            }
                            Spacer()
                            Menu {
                                Button("Rename", systemImage: "pencil") { renaming = section }
                                Button("Move up", systemImage: "arrow.up") { move(section.id, delta: -1) }
                                    .disabled(settings.snapshot.homeSections.first?.id == section.id)
                                Button("Move down", systemImage: "arrow.down") { move(section.id, delta: 1) }
                                    .disabled(settings.snapshot.homeSections.last?.id == section.id)
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = section }
                            } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("Manage \(section.title)")
                        }
                        Toggle("Show on Home", isOn: Binding(get: { section.isVisible }, set: { value in
                            settings.update { state in
                                if let index = state.homeSections.firstIndex(where: { $0.id == section.id }) { state.homeSections[index].isVisible = value }
                            }
                        }))
                        .font(.subheadline)
                    }.padding(.vertical, 4)
                }
                .onMove { offsets, destination in settings.update { $0.homeSections.move(fromOffsets: offsets, toOffset: destination) } }
            } footer: {
                Text("Drag to reorder, or use each section's menu. Hiding or deleting a section does not remove source data or reading progress.")
            }.listRowBackground(MidokuTheme.surface)
        }.settingsStyle().navigationTitle("Home sections")
            .toolbar { EditButton().disabled(settings.snapshot.homeSections.isEmpty) }
            .sheet(item: $renaming) { section in
                NameEditor(title: "Rename section", name: section.title, limit: 100) { value in
                    settings.update { state in
                        if let index = state.homeSections.firstIndex(where: { $0.id == section.id }) { state.homeSections[index].title = value }
                    }
                }
            }
            .confirmationDialog("Delete Home section?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete section", role: .destructive) {
                    if let deleting { settings.update { $0.homeSections.removeAll { $0.id == deleting.id } } }
                    deleting = nil
                }
            } message: { Text("This only removes the shortcut from Home.") }
    }
    private func move(_ id: UUID, delta: Int) {
        settings.update { state in
            guard let index = state.homeSections.firstIndex(where: { $0.id == id }), state.homeSections.indices.contains(index + delta) else { return }
            state.homeSections.swapAt(index, index + delta)
        }
    }
}

struct PinnedHomeView: View {
    let extensions: ExtensionEnvironment
    let browse: () -> Void
    @Environment(AppSettingsStore.self) private var settings
    @State private var refresh = 0
    var body: some View {
        Group {
            if settings.snapshot.homeSections.filter(\.isVisible).isEmpty && settings.snapshot.library.entries.isEmpty {
                MidokuEmptyStateView(kind: .home, action: browse)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        PersonalHomeSections(extensions: extensions)
                        ForEach(settings.snapshot.homeSections.filter(\.isVisible)) { section in
                            HomeShelf(section: section, extensions: extensions, refresh: refresh)
                        }
                    }.padding(.vertical, 16)
                }.refreshable { refresh += 1 }
            }
        }
        .background(MidokuTheme.background).navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink { HomeSectionsSettingsView() } label: { Label("Manage Home sections", systemImage: "slider.horizontal.3") }
        }
    }
}

private struct HomeShelf: View {
    let section: HomeSection
    let extensions: ExtensionEnvironment
    let refresh: Int
    @State private var adapter: (any SourceAdapter)?
    @State private var items: [MangaSummary] = []
    @State private var error: String?
    @State private var retry = 0
    @State private var loading = true
    private var connection: SourceConnection? { extensions.connections.first { $0.id == section.connectionID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title).font(.title3.bold())
                    if let connection {
                        NavigationLink { SourceBrowserView(connection: connection, extensions: extensions) } label: {
                            Text(connection.name).font(.caption)
                        }
                    } else { Text(section.sourceTitle).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                }
                Spacer(minLength: 16)
                if let connection, connection.isEnabled {
                    NavigationLink("View all") {
                        SourceBrowserView(connection: connection, extensions: extensions, initialSection: section)
                    }.font(.subheadline)
                }
            }.padding(.horizontal, 20)
            if connection?.isEnabled != true {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This source is disabled or removed. Your section is kept.").font(.callout)
                    NavigationLink("Manage extensions") { ExtensionManagementView(extensions: extensions) }
                }.padding(.horizontal, 20)
            } else {
                if loading && items.isEmpty { ProgressView("Loading section").padding(.horizontal, 20) }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                        Button("Retry") { retry += 1 }
                    }.padding(.horizontal, 20)
                }
                if let adapter, !items.isEmpty {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items.prefix(10)) { item in
                                NavigationLink { SourceEntryView(summary: item, adapter: adapter, extensions: extensions) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        SourceCoverView(url: item.coverURL, adapter: adapter, extensions: extensions)
                                            .frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text(item.title).font(.subheadline).lineLimit(3).foregroundStyle(MidokuTheme.primaryText)
                                    }.frame(width: 120, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 20)
                    }.scrollIndicators(.hidden)
                } else if !loading && error == nil {
                    Text("No manga in this section yet.").foregroundStyle(MidokuTheme.secondaryText).padding(.horizontal, 20)
                }
            }
        }
        .task(id: "\(refresh)-\(retry)-\(connection?.isEnabled == true)") {
            guard let connection, connection.isEnabled else { loading = false; return }
            loading = true
            defer { loading = false }
            do {
                let current = try await extensions.adapter(for: connection)
                adapter = current
                if let cached = await HomeFeedCache.shared.read(section) {
                    items = cached.items
                    if cached.isFresh && refresh == 0 && retry == 0 { error = nil; return }
                }
                if let feedID = section.feedID {
                    let feeds = try await current.feeds()
                    guard feeds.contains(where: { $0.id == feedID }) else {
                        error = "This feed is no longer available. Choose another feed in Browse and update your Home sections."
                        return
                    }
                }
                let page = if let feedID = section.feedID {
                    try await current.feed(id: feedID, cursor: nil, filters: section.filters)
                } else { try await current.search(query: section.query, cursor: nil, filters: section.filters) }
                try Task.checkCancellation()
                items = Array(page.items.prefix(10)); error = nil
                await HomeFeedCache.shared.write(items, section: section)
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct ReadingHistoryView: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    var body: some View {
        Group {
            if settings.snapshot.history.isEmpty { MidokuEmptyStateView(kind: .history) }
            else {
                List {
                    ForEach(days, id: \.self) { day in
                        Section(day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(settings.snapshot.history.filter { Calendar.current.startOfDay(for: $0.openedAt) == day }) { record in
                                NavigationLink { HistoryReaderDestination(record: record, extensions: extensions) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(record.mangaTitle).font(.headline)
                                        Text(record.chapter.number.map { "Chapter \($0)" } ?? record.chapter.title).font(.subheadline)
                                        Text(record.sourceName).font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                                    }.padding(.vertical, 4)
                                }.swipeActions {
                                    Button("Remove", role: .destructive) { settings.update { $0.history.removeAll { $0.id == record.id } } }
                                }.contextMenu {
                                    Button("Remove from history", systemImage: "trash", role: .destructive) {
                                        settings.update { $0.history.removeAll { $0.id == record.id } }
                                    }
                                }
                            }
                        }.listRowBackground(MidokuTheme.surface)
                    }
                }.settingsStyle()
            }
        }.navigationTitle("History").navigationBarTitleDisplayMode(.inline)
    }
    private var days: [Date] { Array(Set(settings.snapshot.history.map { Calendar.current.startOfDay(for: $0.openedAt) })).sorted(by: >) }
}

private struct HistoryReaderDestination: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    let record: ReadingRecord
    let extensions: ExtensionEnvironment
    @State private var adapter: (any SourceAdapter)?
    @State private var failed = false
    var body: some View {
        Group {
            if let entryID = record.entryID, let slotID = record.slotID,
               settings.snapshot.library.entry(entryID)?.slots.contains(where: { $0.id == slotID }) == true {
                LibraryReaderView(entryID: entryID, initialSlotID: slotID, extensions: extensions)
            } else if let saved = downloads.items.first(where: { $0.record.id == record.id && $0.status == .completed }) {
                SavedChapterReaderDestination(download: saved)
            } else if let adapter {
                SourceChapterReader(mangaID: record.identity.listing.externalID, mangaTitle: record.mangaTitle,
                                    chapter: record.chapter, adapter: adapter, extensions: extensions)
            } else if failed {
                VStack(spacing: 16) {
                    ContentUnavailableView("Source unavailable", systemImage: "exclamationmark.circle",
                        description: Text("Your reading position is kept. Enable or restore the source to read this chapter."))
                    NavigationLink("Manage extensions") { ExtensionManagementView(extensions: extensions) }
                }
            } else { ProgressView("Opening chapter") }
        }.task {
            guard let connection = extensions.connections.first(where: { $0.id == record.identity.listing.connectionID }) else { failed = true; return }
            do { adapter = try await extensions.adapter(for: connection) } catch { failed = true }
        }
    }
}
