import AidokuRunner
import SwiftUI
import UniformTypeIdentifiers

struct MCID: Identifiable { let id: UUID }

private enum MCLibraryGrouping: String, CaseIterable, Identifiable {
    case none, category, artist, author, status, tag, source

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .category: "Category"
        case .artist: "Artist"
        case .author: "Author"
        case .status: "Status"
        case .tag: "Tag"
        case .source: "Source"
        }
    }
}

private enum MCLibraryProgressFilter: String, CaseIterable, Identifiable {
    case all, notStarted, inProgress, completed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Any progress"
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .completed: "Fully read"
        }
    }
}

private struct MCLibraryEntrySection: Identifiable {
    let id: String
    let title: String
    let entries: [MCPersonalEntry]
}

private struct MCLibrarySourceOption: Identifiable, Equatable {
    let id: UUID
    let name: String
}

struct MCCollectionRootView: View {
    @State private var store = MCCollectionStore.shared
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var category: UUID?
    @State private var statuses = Set<MCPersonalStatus>()
    @State private var tags = Set<String>()
    @State private var sources = Set<UUID>()
    @State private var progressFilter = MCLibraryProgressFilter.all
    @State private var grouping = MCLibraryGrouping.none
    @State private var sort = MCLibrarySort.recentlyAdded
    @State private var showCreate = false
    @State private var showCategories = false
    @State private var showImport = false
    @State private var showExport = false
    @State private var document = MCCollectionDocument()
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var confirmDelete = false
    @State private var editingEntry: MCID?
    @State private var showAddPreview = false
    @AppStorage("Midoku.collectionGrid") private var grid = true
    @AppStorage("Midoku.chapterGrid") private var chapterGrid = false
    @AppStorage("Appearance.libraryGridStyle") private var gridStyle = ChapterGridStyle.standard
    @AppStorage("Appearance.libraryPortraitColumns") private var portraitColumns = 3
    @AppStorage("Appearance.libraryLandscapeColumns") private var landscapeColumns = 5

    private func entries(in category: UUID?) -> [MCPersonalEntry] {
        store.library.entries.filter { entry in
            let details = store.library.listing(entry.primaryListingID)?.details
            let searchable = [
                store.library.title(entry),
                entry.authorOverride,
                details?.authors?.joined(separator: " "),
                details?.artists?.joined(separator: " "),
                entryTags(entry).joined(separator: " ")
            ].compactMap { $0 }.joined(separator: " ")
            let sourceIDs = entry.links.compactMap { store.library.listing($0.listingID)?.identity.connectionID }
            return (query.isEmpty || searchable.localizedCaseInsensitiveContains(query)) &&
                (category.map { entry.categoryIDs.contains($0) } ?? true) &&
                (statuses.isEmpty || statuses.contains(entry.status)) &&
                (tags.isEmpty || !tags.isDisjoint(with: Set(entryTags(entry)))) &&
                (sources.isEmpty || !sources.isDisjoint(with: Set(sourceIDs))) &&
                matchesProgress(entry)
        }.sorted { lhs, rhs in
            switch sort {
            case .title: store.library.title(lhs).localizedStandardCompare(store.library.title(rhs)) == .orderedAscending
            case .recentlyRead: (lhs.lastReadAt ?? .distantPast) > (rhs.lastReadAt ?? .distantPast)
            case .recentlyAdded: lhs.createdAt > rhs.createdAt
            case .recentlyUpdated: lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private var hasActiveFilters: Bool {
        !statuses.isEmpty || !tags.isEmpty || !sources.isEmpty || progressFilter != .all
    }

    private var activeFilterCount: Int {
        statuses.count + tags.count + sources.count + (progressFilter == .all ? 0 : 1)
    }

    private var availableTags: [String] {
        Array(Set(store.library.entries.flatMap { entryTags($0) })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableSources: [MCLibrarySourceOption] {
        let ids = Set(store.library.entries.flatMap { entry in
            entry.links.compactMap { store.library.listing($0.listingID)?.identity.connectionID }
        })
        return ids.map { MCLibrarySourceOption(id: $0, name: store.sourceName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func entryTags(_ entry: MCPersonalEntry) -> [String] {
        var seen = Set<String>()
        let listingIDs = [entry.primaryListingID].compactMap { $0 } + entry.links.map(\.listingID)
        return listingIDs.compactMap { store.library.listing($0)?.details.tags }.flatMap { $0 }.filter { tag in
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted
        }
    }

    private func matchesProgress(_ entry: MCPersonalEntry) -> Bool {
        guard progressFilter != .all else { return true }
        let read = entry.slots.filter { store.library.isRead($0) }.count
        switch progressFilter {
        case .all: true
        case .notStarted: read == 0
        case .inProgress: read > 0 && read < entry.slots.count
        case .completed: !entry.slots.isEmpty && read == entry.slots.count
        }
    }

    private func sections(for entries: [MCPersonalEntry]) -> [MCLibraryEntrySection] {
        guard grouping != .none else { return [.init(id: "all", title: "", entries: entries)] }
        let grouped = Dictionary(grouping: entries) { groupTitle($0) }
        let preferredOrder: [String] = switch grouping {
        case .category: store.snapshot.categories.map(\.name) + ["Uncategorized"]
        case .status: MCPersonalStatus.allCases.map(\.title)
        default: []
        }
        return grouped.map { title, values in
            .init(id: "\(grouping.rawValue)-\(title)", title: title, entries: values)
        }.sorted { lhs, rhs in
            let left = preferredOrder.firstIndex(of: lhs.title)
            let right = preferredOrder.firstIndex(of: rhs.title)
            if left != nil || right != nil { return (left ?? Int.max) < (right ?? Int.max) }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func groupTitle(_ entry: MCPersonalEntry) -> String {
        let details = store.library.listing(entry.primaryListingID)?.details
        switch grouping {
        case .none: ""
        case .category:
            store.snapshot.categories.first { entry.categoryIDs.contains($0.id) }?.name ?? "Uncategorized"
        case .artist: details?.artists?.first ?? "Unknown artist"
        case .author: entry.authorOverride ?? details?.authors?.first ?? "Unknown author"
        case .status: entry.status.title
        case .tag: entryTags(entry).first ?? "Untagged"
        case .source:
            entry.primaryListingID.flatMap { store.library.listing($0) }.map { store.sourceName($0.identity.connectionID) }
                ?? "Unavailable source"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if !store.snapshot.categories.isEmpty { categoryTabs }
                if selecting { selectionActions }
                GeometryReader { geometry in
                    TabView(selection: $category) {
                        collectionPage(category: nil, size: geometry.size).tag(Optional<UUID>.none)
                        ForEach(store.snapshot.categories) { item in
                            collectionPage(category: item.id, size: geometry.size).tag(Optional(item.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .customSearchable(text: $query, hidesSearchBarWhenScrolling: false, stacked: false)
            .environment(\.autocorrectionDisabled, true)
            .toolbar {
                if selecting {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { selecting = false; selected.removeAll() } }
                } else {
                    ToolbarItem(placement: .topBarLeading) { groupMenu }
                    ToolbarItem(placement: .topBarLeading) { filterMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create entry")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Select entries", systemImage: "checkmark.circle") { selecting = true; selected.removeAll() }
                            Picker("Sort", selection: $sort) { ForEach(MCLibrarySort.allCases) { Text($0.title).tag($0) } }
                            Toggle("Cover grid", isOn: $grid)
                            Toggle("Chapter grid", isOn: $chapterGrid)
                            Button("Categories", systemImage: "folder") { showCategories = true }
                            Button("Refresh library", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isRefreshing)
                            Divider()
                            Button("Export library", systemImage: "square.and.arrow.up") {
                                do { document = MCCollectionDocument(data: try store.backupData()); showExport = true } catch { store.error = error.localizedDescription }
                            }
                            Button("Import library", systemImage: "square.and.arrow.down") { showImport = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Library options")
                    }
                }
            }
            .confirmationDialog("Remove \(selected.count) entries from library?", isPresented: $confirmDelete) {
                Button("Remove entries", role: .destructive) {
                    if store.removeEntries(selected) { selected.removeAll(); selecting = false }
                }
            } message: { Text("Reading history and downloaded chapters are kept.") }
            .sheet(isPresented: $showCreate) { MCEntryEditor(entryID: nil) }
            .sheet(item: $editingEntry) { MCEntryEditor(entryID: $0.id) }
            .sheet(isPresented: $showCategories) { MCCategoriesView() }
            .sheet(isPresented: $showAddPreview) {
                if let manga = store.snapshot.manga.first?.manga { MCAddSourceView(manga: manga, chapters: []) }
            }
            .fileExporter(isPresented: $showExport, document: document, contentType: .json, defaultFilename: "Midoku-library") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .sheet(isPresented: $showImport) { MCImportCollectionView() }
            .mcErrors(store)
            .navigationDestination(for: UUID.self) { MCEntryView(entryID: $0) }
            .onChange(of: store.snapshot.categories) { _, values in
                if let category, !values.contains(where: { $0.id == category }) { self.category = nil }
            }
            .onChange(of: availableTags) { _, values in tags.formIntersection(values) }
            .onChange(of: availableSources.map(\.id)) { _, values in sources.formIntersection(values) }
            .onChange(of: store.library.entries.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--collection-preview") {
                    try? await Task.sleep(for: .milliseconds(750))
                    if args.contains("--add-preview") { showAddPreview = true }
                    if args.contains("--categories-preview") { showCategories = true }
                    if args.contains("--selection-preview") { selecting = true; selected = Set(store.library.entries.map(\.id)) }
                    if !args.contains("--collection-preview-only"), args.contains("--entry-preview") || args.contains("--edit-preview") || args.contains(where: { $0.hasPrefix("--chapter-") }) || args.contains("--reader-preview") || args.contains("--reader-hidden-preview"), let id = MCCollectionPreview.entryID { path = [id] }
                    return
                }
                #endif
                await store.adoptExistingLibrary()
            }
        }.midokuAccent()
    }

    private var categoryTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    categoryButton("All", count: store.library.entries.count, id: nil)
                    ForEach(store.snapshot.categories) { item in
                        categoryButton(item.name, count: store.library.entries.filter { $0.categoryIDs.contains(item.id) }.count, id: item.id)
                    }
                }.padding(.horizontal)
            }
            .onChange(of: category) { _, value in
                withAnimation { proxy.scrollTo(value?.uuidString ?? "all", anchor: .center) }
            }
        }.fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var selectionActions: some View {
        HStack {
            Button(selected.isEmpty ? "Select all" : "Deselect all") {
                if selected.isEmpty { selected = Set(entries(in: category).map(\.id)) } else { selected.removeAll() }
            }
            Spacer()
            Text("\(selected.count) selected").font(.subheadline).foregroundStyle(.secondary)
            Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                .disabled(selected.isEmpty).accessibilityLabel("Remove selected entries")
                .padding(.leading, 12)
        }.padding().background(.bar)
    }

    private func columns(for size: CGSize) -> [GridItem] {
        let count = grid ? (size.width > size.height ? min(10, max(2, landscapeColumns)) : min(6, max(2, portraitColumns))) : 1
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    @ViewBuilder private func collectionPage(category: UUID?, size: CGSize) -> some View {
        let values = entries(in: category)
        if values.isEmpty {
            let libraryIsEmpty = store.library.entries.isEmpty
            UnavailableView(libraryIsEmpty ? "Library Empty" : "No matches", systemImage: "books.vertical.fill",
                description: Text(libraryIsEmpty ? "Add a title from Browse, or create an entry." : "Try another search, category, or filter."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(sections(for: values)) { section in
                        if grouping != .none {
                            HStack(spacing: 8) {
                                Text(section.title).font(.headline)
                                Text("\(section.entries.count)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        LazyVGrid(columns: columns(for: size), alignment: .leading, spacing: grid ? 20 : 14) {
                            ForEach(section.entries) { entry in entryButton(entry) }
                        }.padding(.horizontal)
                    }
                }.padding(.vertical)
            }.refreshable { await store.refresh() }
        }
    }

    private func categoryButton(_ name: String, count: Int, id: UUID?) -> some View {
        Button { withAnimation { category = id } } label: {
            HStack(spacing: 6) {
                Text(name).font(.subheadline.weight(category == id ? .semibold : .medium))
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(category == id ? Color.accentColor : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(uiColor: category == id ? UIColor.tertiarySystemFill : UIColor.secondarySystemFill), in: Capsule())
            }
            .foregroundStyle(category == id ? Color.accentColor : .secondary)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if category == id { Capsule().fill(Color.accentColor).frame(height: 3) }
            }
        }.buttonStyle(.plain).id(id?.uuidString ?? "all")
        .accessibilityAddTraits(category == id ? .isSelected : [])
    }

    private func entryButton(_ entry: MCPersonalEntry) -> some View {
        Button {
            if selecting { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } }
            else { path.append(entry.id) }
        } label: {
            entryLabel(entry).overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Circle().fill(Color.accentColor)).padding(8)
                }
            }
        }.buttonStyle(.plain)
        .accessibilityLabel("\(store.library.title(entry)), \(entry.slots.count) chapters, \(entry.status.title)")
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Edit entry", systemImage: "pencil") { editingEntry = MCID(id: entry.id) }
            Button("Select entry", systemImage: "checkmark.circle") { selected.insert(entry.id); selecting = true }
            Button("Remove from library", systemImage: "trash", role: .destructive) {
                selected = [entry.id]; confirmDelete = true
            }
        }
    }

    private var groupMenu: some View {
        Menu {
            Picker("Group by", selection: $grouping) {
                ForEach(MCLibraryGrouping.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: grouping == .none ? "rectangle.3.group" : "rectangle.3.group.fill")
        }
        .accessibilityLabel(grouping == .none ? "Group library" : "Grouped by \(grouping.title)")
    }

    private var filterMenu: some View {
        Menu {
            Menu("Status", systemImage: "bookmark") {
                ForEach(MCPersonalStatus.allCases) { item in
                    Toggle(item.title, isOn: Binding(
                        get: { statuses.contains(item) },
                        set: { if $0 { statuses.insert(item) } else { statuses.remove(item) } }
                    ))
                }
            }
            Picker("Reading progress", selection: $progressFilter) {
                ForEach(MCLibraryProgressFilter.allCases) { Text($0.title).tag($0) }
            }
            if !availableTags.isEmpty {
                Menu("Tags", systemImage: "tag") {
                    ForEach(availableTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { tags.contains(tag) },
                            set: { if $0 { tags.insert(tag) } else { tags.remove(tag) } }
                        ))
                    }
                }
            }
            if !availableSources.isEmpty {
                Menu("Source", systemImage: "globe") {
                    ForEach(availableSources, id: \.id) { source in
                        Toggle(source.name, isOn: Binding(
                            get: { sources.contains(source.id) },
                            set: { if $0 { sources.insert(source.id) } else { sources.remove(source.id) } }
                        ))
                    }
                }
            }
            if hasActiveFilters {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                    statuses.removeAll(); tags.removeAll(); sources.removeAll(); progressFilter = .all
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if hasActiveFilters {
                    Text("\(activeFilterCount)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 13, minHeight: 13).background(Color.accentColor, in: Circle()).offset(x: 5, y: -5)
                }
            }
        }
        .accessibilityLabel(hasActiveFilters ? "Library filters, \(activeFilterCount) active" : "Filter library")
    }

    @ViewBuilder private func entryLabel(_ entry: MCPersonalEntry) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 7) {
                MCEntryCover(entry: entry)
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        if gridStyle == .compact {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.library.title(entry)).font(.caption.weight(.semibold)).lineLimit(2)
                                Text("\(entry.slots.count) chapters").font(.caption2).opacity(0.85).lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.top, 28)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: gridStyle == .clean ? 6 : 10))
                if gridStyle == .standard {
                    Text(store.library.title(entry)).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(entry.slots.count) chapters · \(entry.status.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                entryTagRow(entry)
            }
        } else {
            HStack(spacing: 14) {
                MCEntryCover(entry: entry).frame(width: 66, height: 99).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.library.title(entry)).font(.headline).lineLimit(2)
                    Text(entry.status.title).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(entry.slots.count) chapters · \(entry.links.count) sources").font(.caption).foregroundStyle(.secondary)
                    entryTagRow(entry)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder private func entryTagRow(_ entry: MCPersonalEntry) -> some View {
        let values = entryTags(entry)
        if !values.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(values.prefix(2)), id: \.self) { tag in
                    Text(tag).font(.caption2.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.11), in: Capsule())
                }
                if values.count > 2 {
                    Text("+\(values.count - 2)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MCEntryCover: View {
    let entry: MCPersonalEntry
    @State private var store = MCCollectionStore.shared
    var body: some View {
        GeometryReader { geometry in
            if let id = entry.coverID, let data = store.library.covers.first(where: { $0.id == id })?.data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else if !entry.hidesCover, let listing = store.library.listing(entry.primaryListingID), let cover = listing.details.coverURL {
                SourceImageView(source: store.source(listing.identity.connectionID), imageUrl: cover.absoluteString,
                    width: geometry.size.width, height: geometry.size.height, placeholder: "MidokuCoverPlaceholder").clipped()
            } else {
                Image("MidokuCoverPlaceholder").resizable().scaledToFill()
            }
        }.accessibilityHidden(true)
    }
}

struct MCCollectionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension View {
    func mcErrors(_ store: MCCollectionStore) -> some View {
        alert("Library", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct MCImportCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var picking = false
    @State private var incoming: Data?
    @State private var count = 0
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose library backup") { picking = true }
                    if incoming != nil {
                        Text("\(count) entries ready to restore")
                        Text("This replaces this app’s library, including its categories and edits. Downloads and source installations are kept.").foregroundStyle(.secondary)
                        Button("Restore library", role: .destructive) {
                            guard let incoming else { return }
                            do { try store.restore(incoming); dismiss() } catch { store.error = error.localizedDescription }
                        }
                    }
                }
            }.navigationTitle("Import library").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 128 * 1024 * 1024 else { throw MCLibraryFailure.invalid }
                        let data = try Data(contentsOf: url)
                        let snapshot = try JSONDecoder().decode(MCCollectionSnapshot.self, from: data)
                        try snapshot.validate(); count = snapshot.library.entries.count; incoming = data
                    } catch { store.error = error.localizedDescription }
                }.mcErrors(store)
        }
    }
}
