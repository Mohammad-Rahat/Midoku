import AidokuRunner
import SwiftUI
import UniformTypeIdentifiers

struct MCID: Identifiable { let id: UUID }

struct MCCollectionRootView: View {
    @State private var store = MCCollectionStore.shared
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var category: UUID?
    @State private var status: MCPersonalStatus?
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
    @AppStorage("Appearance.layout") private var layout = AppearanceSettings.Layout.standard
    @AppStorage("Appearance.customPortraitRows") private var portraitColumns = UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2
    @AppStorage("Appearance.customLandscapeRows") private var landscapeColumns = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4

    private func entries(in category: UUID?) -> [MCPersonalEntry] {
        store.library.entries.filter { entry in
            (query.isEmpty || store.library.title(entry).localizedCaseInsensitiveContains(query)) &&
            (category.map { entry.categoryIDs.contains($0) } ?? true) && (status == nil || entry.status == status)
        }.sorted { lhs, rhs in
            switch sort {
            case .title: store.library.title(lhs).localizedStandardCompare(store.library.title(rhs)) == .orderedAscending
            case .recentlyRead: (lhs.lastReadAt ?? .distantPast) > (rhs.lastReadAt ?? .distantPast)
            case .recentlyAdded: lhs.createdAt > rhs.createdAt
            case .recentlyUpdated: lhs.updatedAt > rhs.updatedAt
            }
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
            .navigationTitle("Collection")
            .searchable(text: $query, prompt: "Search collection")
            .toolbar {
                if selecting {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { selecting = false; selected.removeAll() } }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create entry")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Select entries", systemImage: "checkmark.circle") { selecting = true; selected.removeAll() }
                            Picker("Sort", selection: $sort) { ForEach(MCLibrarySort.allCases) { Text($0.title).tag($0) } }
                            Picker("Status", selection: $status) {
                                Text("All statuses").tag(Optional<MCPersonalStatus>.none)
                                ForEach(MCPersonalStatus.allCases) { Text($0.title).tag(Optional($0)) }
                            }
                            Toggle("Cover grid", isOn: $grid)
                            Toggle("Chapter grid", isOn: $chapterGrid)
                            Button("Categories", systemImage: "folder") { showCategories = true }
                            Button("Refresh collection", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isRefreshing)
                            Divider()
                            Button("Export collection", systemImage: "square.and.arrow.up") {
                                do { document = MCCollectionDocument(data: try store.backupData()); showExport = true } catch { store.error = error.localizedDescription }
                            }
                            Button("Import collection", systemImage: "square.and.arrow.down") { showImport = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Collection options")
                    }
                }
            }
            .confirmationDialog("Remove \(selected.count) entries from collection?", isPresented: $confirmDelete) {
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
            .fileExporter(isPresented: $showExport, document: document, contentType: .json, defaultFilename: "Midoku-collection") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .sheet(isPresented: $showImport) { MCImportCollectionView() }
            .mcErrors(store)
            .navigationDestination(for: UUID.self) { MCEntryView(entryID: $0) }
            .onChange(of: store.snapshot.categories) { _, values in
                if let category, !values.contains(where: { $0.id == category }) { self.category = nil }
            }
            .onChange(of: store.library.entries.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--collection-preview") {
                    if args.contains("--add-preview") { showAddPreview = true }
                    if args.contains("--categories-preview") { showCategories = true }
                    if args.contains("--selection-preview") { selecting = true; selected = Set(store.library.entries.map(\.id)) }
                    if !args.contains("--collection-preview-only"), args.contains("--entry-preview") || args.contains("--edit-preview") || args.contains("--paste-preview") || args.contains("--chapter-selection-preview") || args.contains("--reader-preview"), let id = MCCollectionPreview.entryID { path = [id] }
                    return
                }
                #endif
                await store.adoptExistingLibrary()
            }
        }
    }

    private var categoryTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    categoryButton("All", id: nil)
                    ForEach(store.snapshot.categories) { categoryButton($0.name, id: $0.id) }
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
        let count: Int
        if !grid { count = 1 }
        else {
            switch layout {
            case .standard: count = max(1, Int(size.width / 180))
            case .compact: count = max(1, Int(size.width / (UIDevice.current.userInterfaceIdiom == .pad ? 150 : 120)))
            case .custom: count = max(1, size.width > size.height ? landscapeColumns : portraitColumns)
            }
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    @ViewBuilder private func collectionPage(category: UUID?, size: CGSize) -> some View {
        let values = entries(in: category)
        if values.isEmpty {
            ContentUnavailableView {
                Image("MidokuEmptyLibrary").resizable().scaledToFit().frame(width: 160, height: 130)
                Text(query.isEmpty ? "Your collection" : "No matches")
            } description: {
                Text(query.isEmpty ? "Add a title from Browse, or create an entry." : "Try another title or category.")
            } actions: { Button("Create entry") { showCreate = true } }
        } else {
            ScrollView {
                LazyVGrid(columns: columns(for: size), alignment: .leading, spacing: grid ? 20 : 14) {
                    ForEach(values) { entry in
                        Button {
                            if selecting { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } }
                            else { path.append(entry.id) }
                        } label: {
                            entryLabel(entry).overlay(alignment: .topTrailing) {
                                if selecting {
                                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.accentColor).padding(8)
                                }
                            }
                        }.buttonStyle(.plain)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Button("Edit entry", systemImage: "pencil") { editingEntry = MCID(id: entry.id) }
                            Button("Select entry", systemImage: "checkmark.circle") { selected.insert(entry.id); selecting = true }
                            Button("Remove from collection", systemImage: "trash", role: .destructive) {
                                selected = [entry.id]; confirmDelete = true
                            }
                        }
                    }
                }.padding()
            }.refreshable { await store.refresh() }
        }
    }

    private func categoryButton(_ name: String, id: UUID?) -> some View {
        Button { withAnimation { category = id } } label: {
            Text(name).font(.subheadline.weight(category == id ? .semibold : .regular))
                .foregroundStyle(category == id ? Color.accentColor : .secondary)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { if category == id { Rectangle().frame(height: 2) } }
        }.buttonStyle(.plain).id(id?.uuidString ?? "all")
        .accessibilityAddTraits(category == id ? .isSelected : [])
    }

    @ViewBuilder private func entryLabel(_ entry: MCPersonalEntry) -> some View {
        if grid {
            VStack(alignment: .leading, spacing: 7) {
                MCEntryCover(entry: entry).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                Text(store.library.title(entry)).font(.subheadline.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(entry.slots.count) chapters · \(entry.status.title)").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 14) {
                MCEntryCover(entry: entry).frame(width: layout == .compact ? 48 : 66, height: layout == .compact ? 72 : 99).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.library.title(entry)).font(.headline).lineLimit(2)
                    Text(entry.status.title).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(entry.slots.count) chapters · \(entry.links.count) sources").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
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
        alert("Collection", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
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
                    Button("Choose collection backup") { picking = true }
                    if incoming != nil {
                        Text("\(count) entries ready to restore")
                        Text("This replaces this app’s collection, including its categories, edits and clipboard. Downloads and source installations are kept.").foregroundStyle(.secondary)
                        Button("Restore collection", role: .destructive) {
                            guard let incoming else { return }
                            do { try store.restore(incoming); dismiss() } catch { store.error = error.localizedDescription }
                        }
                    }
                }
            }.navigationTitle("Import collection").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
