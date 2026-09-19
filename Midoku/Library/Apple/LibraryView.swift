import SwiftUI
import UIKit

struct LibraryView: View {
    let extensions: ExtensionEnvironment
    let browse: () -> Void
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.gridLandscape) private var gridLandscape
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var category = "all"
    @State private var status: PersonalStatus?
    @State private var unreadOnly = false
    @State private var downloadedOnly = false
    @State private var sourceID: UUID?
    @State private var publication = "all"
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var creating = false
    @State private var assigning = false
    @State private var removing = false
    @State private var message: String?
    @AppStorage("libraryListLayout") private var listLayout = false

    private var state: LibraryState { settings.snapshot.library }
    private var categoryIDs: [String] { ["all", "uncategorized"] + settings.snapshot.categories.map { $0.id.uuidString } }
    private var visible: [PersonalEntry] { visible(in: category) }
    private func visible(in category: String) -> [PersonalEntry] {
        let downloaded = Set(downloads.items.filter { $0.status == .completed }.map { $0.record.id })
        return state.entries.filter { entry in
            (submittedQuery.isEmpty || state.title(entry).localizedStandardContains(submittedQuery)) &&
            (category == "all" || (category == "uncategorized" ? entry.categoryIDs.isEmpty : entry.categoryIDs.contains { $0.uuidString == category })) &&
            (status == nil || entry.status == status) && (!unreadOnly || entry.slots.contains { !state.isRead($0) }) &&
            (!downloadedOnly || entry.slots.contains { $0.preferred.flatMap { state.chapter($0.chapterID) }.map { downloaded.contains($0.identity) } == true }) &&
            (sourceID == nil || entry.links.contains { state.listing($0.listingID)?.identity.connectionID == sourceID }) &&
            (publication == "all" || state.listing(entry.primaryListingID)?.details.status?.lowercased() == publication)
        }.sorted { lhs, rhs in
            switch settings.snapshot.preferences.librarySort {
            case .title: return state.title(lhs).localizedStandardCompare(state.title(rhs)) == .orderedAscending
            case .recentlyAdded: return lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt > rhs.createdAt
            case .recentlyUpdated: return lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
            case .recentlyRead: return (lhs.lastReadAt ?? .distantPast) == (rhs.lastReadAt ?? .distantPast) ? lhs.createdAt > rhs.createdAt : (lhs.lastReadAt ?? .distantPast) > (rhs.lastReadAt ?? .distantPast)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            if !state.entries.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MidokuTheme.secondaryText)
                    TextField("Search your library", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).onSubmit { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if !query.isEmpty { Button { query = ""; submittedQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                    filterMenu
                }.padding(12).background(MidokuTheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16).padding(.vertical, 8)
                categoryTabs
                HStack {
                    Menu {
                        Picker("Sort", selection: settings.binding(\.librarySort)) {
                            ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: { Label(settings.snapshot.preferences.librarySort.title, systemImage: "chevron.down").font(.caption) }
                    Spacer()
                    NavigationLink { LibrarySettingsView() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 20)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Library layout and settings")
                }.foregroundStyle(MidokuTheme.secondaryText).padding(.horizontal, 16)
            }
            if state.entries.isEmpty {
                MidokuEmptyStateView(kind: .library, action: browse)
            } else {
                TabView(selection: $category) {
                    ForEach(categoryIDs, id: \.self) { id in
                        categoryPage(id, width: geometry.size.width, landscape: gridLandscape).tag(id)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
            }
            if library.refreshing { ProgressView("Refreshing library…").font(.caption).padding(8) }
            if let message = message ?? library.refreshMessage { Text(message).font(.caption).foregroundStyle(MidokuTheme.secondaryText).padding(.horizontal, 16) }
        }
        }
        .mainScreenHeader(selecting ? "\(selected.count) selected" : "Library") {
            HStack(spacing: 16) {
                Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }.font(.subheadline).buttonStyle(.plain).frame(minHeight: 44).disabled(state.entries.isEmpty)
                Menu {
                    Button("New empty entry", systemImage: "plus") { creating = true }
                    Button("Find manga", systemImage: "magnifyingglass", action: browse)
                    if !state.clipboard.isEmpty { NavigationLink { ClipboardView() } label: { Label("Clipboard (\(state.clipboard.count))", systemImage: "doc.on.clipboard") } }
                    Button("Refresh library", systemImage: "arrow.clockwise") { Task { await library.refresh() } }.disabled(library.refreshing)
                    Toggle("List layout", isOn: $listLayout)
                    Picker("Sort", selection: settings.binding(\.librarySort)) { ForEach(LibrarySort.allCases) { Text($0.title).tag($0) } }
                } label: { Image(systemName: "plus").accessibilityLabel("Library actions") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Button("Select all") { selected = Set(visible.map(\.id)) }
                    Spacer()
                    Menu("Actions", systemImage: "ellipsis.circle") {
                        Button("Set categories", systemImage: "folder") { assigning = true }
                        ForEach(PersonalStatus.allCases) { status in Button("Status: \(status.title)") { bulk { state in for id in selected { try state.library.editEntry(id) { $0.status = status } } } } }
                        Button("Mark read", systemImage: "checkmark.circle") { mark(read: true) }
                        Button("Mark unread", systemImage: "circle") { mark(read: false) }
                        Button("Download unread", systemImage: "arrow.down.circle") { downloadSelection() }
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await library.refresh(entryIDs: selected) } }
                        Button("Remove from library", systemImage: "trash", role: .destructive) { removing = true }
                    }.disabled(selected.isEmpty)
                }.padding(16).background(MidokuTheme.surface)
            }
        }
        .sheet(isPresented: $creating) { EntryEditor(entry: PersonalEntry(), isNew: true, extensions: extensions) }
        .sheet(isPresented: $assigning) { CategoryAssignmentView(entryIDs: selected) }
        .confirmationDialog("Remove \(selected.count) entries?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove entries", role: .destructive) { let ids = selected; bulk { $0.library.removeEntries(ids) }; selected.removeAll(); selecting = false }
        } message: { Text("Your downloaded chapters, History, and shared reading progress will be kept.") }
        .onChange(of: settings.snapshot.categories) { if category != "all", category != "uncategorized", !settings.snapshot.categories.contains(where: { $0.id.uuidString == category }) { category = "all" } }
    }

    private var categoryTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(categoryIDs, id: \.self) { id in
                        Button { category = id } label: {
                            Text(categoryTitle(id)).font(.subheadline.weight(category == id ? .semibold : .regular))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .foregroundStyle(category == id ? MidokuTheme.onAccent : MidokuTheme.secondaryText)
                                .background(category == id ? settings.snapshot.preferences.accent.fill : MidokuTheme.elevated, in: Capsule())
                                .frame(minHeight: 44)
                        }.buttonStyle(.plain).id(id)
                            .accessibilityAddTraits(category == id ? .isSelected : [])
                    }
                }.padding(.horizontal, 16)
            }.scrollIndicators(.hidden)
                .onChange(of: category) { proxy.scrollTo(category, anchor: .center) }
        }
    }
    private func categoryTitle(_ id: String) -> String {
        if id == "all" { return "All" }
        if id == "uncategorized" { return "Uncategorized" }
        return settings.snapshot.categories.first { $0.id.uuidString == id }?.name ?? "Category"
    }
    private func categoryPage(_ id: String, width: CGFloat, landscape: Bool) -> some View {
        let entries = visible(in: id)
        let count = settings.snapshot.preferences.resolvedLibraryLayout.columns(landscape: landscape)
        let cellWidth = max(1, (width - 32 - CGFloat(count - 1) * 12) / CGFloat(count))
        return ScrollView {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(query.isEmpty ? "No entries here" : "No matches", systemImage: "books.vertical",
                        description: Text(query.isEmpty ? "Add entries to this category or adjust your filters." : "Try another title or adjust your filters."))
                    Button("Reset filters") { query = ""; submittedQuery = ""; status = nil; sourceID = nil; publication = "all"; unreadOnly = false; downloadedOnly = false }
                }.padding(.top, 32)
            } else if listLayout || textSize.isAccessibilitySize {
                LazyVStack(spacing: 12) { ForEach(entries) { entry in entryLink(entry, compact: true) } }.padding(16)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 12, alignment: .top), count: count), alignment: .leading, spacing: 20) {
                    ForEach(entries) { entry in entryLink(entry, compact: false, width: cellWidth) }
                }.padding(16)
            }
        }.refreshable { await library.refresh() }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Unread only", isOn: $unreadOnly)
            Toggle("Downloaded only", isOn: $downloadedOnly)
            Picker("Reading status", selection: $status) { Text("Any status").tag(PersonalStatus?.none); ForEach(PersonalStatus.allCases) { Text($0.title).tag(Optional($0)) } }
            Picker("Source", selection: $sourceID) { Text("All sources").tag(UUID?.none); ForEach(settings.snapshot.connections) { Text($0.name).tag(Optional($0.id)) } }
            Picker("Publication", selection: $publication) { Text("Any publication").tag("all"); ForEach(["ongoing", "completed", "hiatus", "cancelled"], id: \.self) { Text($0.capitalized).tag($0) } }
        } label: { Image(systemName: "line.3.horizontal.decrease").font(.system(size: 20)).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Filter library")
    }
    @ViewBuilder private func entryLink(_ entry: PersonalEntry, compact: Bool, width: CGFloat? = nil) -> some View {
        if selecting {
            Button { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } } label: { card(entry, compact: compact, width: width) }.buttonStyle(.plain)
        } else {
            NavigationLink { LibraryEntryView(entryID: entry.id, extensions: extensions) } label: { card(entry, compact: compact, width: width) }.buttonStyle(.plain)
                .contextMenu { Button("Select entry", systemImage: "checkmark.circle") { selecting = true; selected = [entry.id] } }
        }
    }
    private func card(_ entry: PersonalEntry, compact: Bool, width: CGFloat?) -> some View {
        let layout = compact ? AnyLayout(HStackLayout(alignment: .center, spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            LibraryCoverView(entry: entry, extensions: extensions)
                .frame(width: compact ? 64 : width, height: compact ? 96 : (width ?? 140) * 1.5)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if selecting { Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.white, .green).padding(6) }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(state.title(entry)).font(.subheadline.weight(.semibold)).lineLimit(compact ? 3 : 2).foregroundStyle(MidokuTheme.primaryText)
                Text("\(entry.slots.filter { !state.isRead($0) }.count) unread · \(entry.status.title)").font(.caption).foregroundStyle(MidokuTheme.secondaryText)
            }
            if compact { Spacer(minLength: 0) }
        }.frame(width: compact ? nil : width, alignment: .leading).frame(maxWidth: compact ? .infinity : nil, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func bulk(_ action: @escaping (inout AppSnapshot) throws -> Void) { Task { do { try await settings.commit(action) } catch { message = error.localizedDescription } } }
    private func mark(read: Bool) { let ids = selected; bulk { state in for id in ids { if let entry = state.library.entry(id) { try state.markSlots(entryID: id, slots: Set(entry.slots.map(\.id)), read: read) } } } }
    private func downloadSelection() {
        let entries = state.entries.filter { selected.contains($0.id) }
        Task { for entry in entries { for slot in entry.slots where !state.isRead(slot) { if let variant = slot.preferred, let record = settings.snapshot.library.readingRecord(variant.chapterID, connections: settings.snapshot.connections, entryID: entry.id, slotID: slot.id) { await downloads.enqueue(record) } } } }
    }
}

struct LibraryCoverView: View {
    let entry: PersonalEntry
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @State private var adapter: (any SourceAdapter)?
    private var listing: LibraryListing? { settings.snapshot.library.listing(entry.primaryListingID) }
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let id = entry.coverID, let data = settings.snapshot.library.covers.first(where: { $0.id == id })?.data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if !entry.hidesCover, let adapter {
                    SourceCoverView(url: listing?.details.coverURL, adapter: adapter, extensions: extensions)
                } else { Image("MidokuCoverPlaceholder").resizable().scaledToFit().background(MidokuTheme.elevated) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true).task(id: "\(listing?.id.uuidString ?? "none")-\(extensions.isReady)") {
            guard let listing, let connection = extensions.connections.first(where: { $0.id == listing.identity.connectionID }) else { adapter = nil; return }
            adapter = try? await extensions.adapter(for: connection)
        }
    }
}

nonisolated extension LibraryState {
    func readingRecord(_ chapterID: UUID, connections: [SourceConnection], entryID: UUID? = nil, slotID: UUID? = nil) -> ReadingRecord? {
        guard let chapter = chapter(chapterID), let listing = listings.first(where: { $0.identity == chapter.identity.listing }) else { return nil }
        return ReadingRecord(identity: chapter.identity, mangaTitle: entryID.flatMap { entry($0) }.map { title($0) } ?? listing.details.title,
            sourceName: connections.first(where: { $0.id == chapter.identity.listing.connectionID })?.name ?? "Unavailable source", chapter: chapter.record, openedAt: Date(), entryID: entryID, slotID: slotID)
    }
}
