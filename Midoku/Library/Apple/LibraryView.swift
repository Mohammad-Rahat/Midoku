import SwiftUI
import UIKit

struct LibraryView: View {
    let extensions: ExtensionEnvironment
    let browse: () -> Void
    @Environment(AppSettingsStore.self) private var settings
    @Environment(LibraryCoordinator.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var query = ""
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
    private var visible: [PersonalEntry] {
        let downloaded = Set(downloads.items.filter { $0.status == .completed }.map { $0.record.id })
        return state.entries.filter { entry in
            (query.isEmpty || state.title(entry).localizedStandardContains(query)) &&
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
        VStack(spacing: 0) {
            if !state.entries.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MidokuTheme.secondaryText)
                    TextField("Search your library", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                    filterMenu
                }.padding(12).background(MidokuTheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16).padding(.vertical, 8)
                Picker("Category", selection: $category) {
                    Text("All · \(state.entries.count)").tag("all")
                    Text("Uncategorized").tag("uncategorized")
                    ForEach(settings.snapshot.categories) { Text($0.name).tag($0.id.uuidString) }
                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }
            if state.entries.isEmpty {
                MidokuEmptyStateView(kind: .library, action: browse)
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
                Button("Reset filters") { query = ""; category = "all"; status = nil; sourceID = nil; publication = "all"; unreadOnly = false; downloadedOnly = false }.padding()
            } else {
                ScrollView {
                    if listLayout || textSize.isAccessibilitySize {
                        LazyVStack(spacing: 12) { ForEach(visible) { entry in entryLink(entry, compact: true) } }.padding(16)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: settings.snapshot.preferences.coverDensity.minimumWidth), spacing: 14)], alignment: .leading, spacing: 20) {
                            ForEach(visible) { entry in entryLink(entry, compact: false) }
                        }.padding(16)
                    }
                }.refreshable { await library.refresh() }
            }
            if library.refreshing { ProgressView("Refreshing library…").font(.caption).padding(8) }
            if let message = message ?? library.refreshMessage { Text(message).font(.caption).foregroundStyle(MidokuTheme.secondaryText).padding(.horizontal, 16) }
        }
        .background(MidokuTheme.background).navigationTitle(selecting ? "\(selected.count) selected" : "Library").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }.disabled(state.entries.isEmpty)
                Menu {
                    Button("New empty entry", systemImage: "plus") { creating = true }
                    Button("Find manga", systemImage: "magnifyingglass", action: browse)
                    NavigationLink { ClipboardView() } label: { Label("Clipboard (\(state.clipboard.count))", systemImage: "doc.on.clipboard") }
                    Button("Refresh library", systemImage: "arrow.clockwise") { Task { await library.refresh() } }.disabled(library.refreshing)
                    Toggle("List layout", isOn: $listLayout)
                    Picker("Sort", selection: settings.binding(\.librarySort)) { ForEach(LibrarySort.allCases) { Text($0.title).tag($0) } }
                } label: { Image(systemName: "plus.circle").accessibilityLabel("Library actions") }
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

    private var filterMenu: some View {
        Menu {
            Toggle("Unread only", isOn: $unreadOnly)
            Toggle("Downloaded only", isOn: $downloadedOnly)
            Picker("Reading status", selection: $status) { Text("Any status").tag(PersonalStatus?.none); ForEach(PersonalStatus.allCases) { Text($0.title).tag(Optional($0)) } }
            Picker("Source", selection: $sourceID) { Text("All sources").tag(UUID?.none); ForEach(settings.snapshot.connections) { Text($0.name).tag(Optional($0.id)) } }
            Picker("Publication", selection: $publication) { Text("Any publication").tag("all"); ForEach(["ongoing", "completed", "hiatus", "cancelled"], id: \.self) { Text($0.capitalized).tag($0) } }
        } label: { Image(systemName: "line.3.horizontal.decrease").frame(minWidth: 36, minHeight: 32) }.accessibilityLabel("Filter library")
    }
    @ViewBuilder private func entryLink(_ entry: PersonalEntry, compact: Bool) -> some View {
        if selecting {
            Button { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } } label: { card(entry, compact: compact) }.buttonStyle(.plain)
        } else {
            NavigationLink { LibraryEntryView(entryID: entry.id, extensions: extensions) } label: { card(entry, compact: compact) }.buttonStyle(.plain)
                .contextMenu { Button("Select entry", systemImage: "checkmark.circle") { selecting = true; selected = [entry.id] } }
        }
    }
    private func card(_ entry: PersonalEntry, compact: Bool) -> some View {
        let layout = compact ? AnyLayout(HStackLayout(alignment: .center, spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            LibraryCoverView(entry: entry, extensions: extensions)
                .frame(width: compact ? 64 : nil, height: compact ? 90 : 190).frame(maxWidth: compact ? nil : .infinity)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if selecting { Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.white, .green).padding(6) }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(state.title(entry)).font(.subheadline.weight(.semibold)).lineLimit(compact ? 3 : 2).foregroundStyle(MidokuTheme.primaryText)
                Text("\(entry.slots.filter { !state.isRead($0) }.count) unread · \(entry.status.title)").font(.caption).foregroundStyle(MidokuTheme.secondaryText)
            }
            if compact { Spacer(minLength: 0) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
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
    var overrideID: UUID? = nil
    @Environment(AppSettingsStore.self) private var settings
    @State private var adapter: (any SourceAdapter)?
    private var listing: LibraryListing? { settings.snapshot.library.listing(entry.primaryListingID) }
    var body: some View {
        Group {
            if let id = overrideID ?? entry.coverID, let data = settings.snapshot.library.covers.first(where: { $0.id == id })?.data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if !entry.hidesCover, let adapter {
                SourceCoverView(url: listing?.details.coverURL, adapter: adapter, extensions: extensions)
            } else { Image("MidokuCoverPlaceholder").resizable().scaledToFit().background(MidokuTheme.elevated) }
        }.accessibilityHidden(true).task(id: listing?.id) {
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
