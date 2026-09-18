import SwiftUI

struct SourceBrowserView: View {
    let connection: SourceConnection
    let extensions: ExtensionEnvironment
    @State private var adapter: (any SourceAdapter)?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let adapter {
                SourceBrowserContent(adapter: adapter, extensions: extensions)
            } else if let errorMessage {
                SourceErrorView(message: errorMessage) { retry += 1 }
            } else {
                ProgressView("Opening source")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MidokuTheme.background)
        .navigationTitle(connection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) {
            do {
                adapter = try await extensions.adapter(for: connection)
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

nonisolated private enum SourceBrowseTab: Hashable, Sendable {
    case feed(String)
    case search
}

nonisolated private struct BrowseRequest: Equatable, Sendable {
    let feedID: String?
    let query: String
    let filters: SourceFilterValues
    let submitted: Bool
    let revision: Int

    func hasSameResults(as other: BrowseRequest) -> Bool {
        feedID == other.feedID && query == other.query && filters == other.filters && revision == other.revision
    }

    func fetch(adapter: any SourceAdapter, cursor: String?) async throws -> SourcePage<MangaSummary> {
        if let feedID { return try await adapter.feed(id: feedID, cursor: cursor, filters: filters) }
        return try await adapter.search(query: query, cursor: cursor, filters: filters)
    }
}

private struct SourceBrowserContent: View {
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var results = SourcePageStore<MangaSummary>()
    @State private var feeds: [FeedDescriptor] = []
    @State private var selectedTab: SourceBrowseTab?
    @State private var feedError: String?
    @State private var feedRetry = 0
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var submittedQuery: String?
    @State private var filters: SourceFilterValues = [:]
    @State private var filterDefinitions: [SourceSearchFilter]?
    @State private var showingFilters = false
    @State private var revision = 0
    @State private var pageRequest = 0
    @State private var loadedRequest: BrowseRequest?
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var request: BrowseRequest? {
        guard let selectedTab else { return nil }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedID: String?
        switch selectedTab {
        case .feed(let id): feedID = id
        case .search: feedID = nil
        }
        let scope: SourceSearchFilter.Scope = feedID == nil ? .search : .feed
        let scopedFilters: SourceFilterValues
        if let filterDefinitions {
            let visibleIDs = Set(filterDefinitions.filter { $0.scopes.contains(scope) }.map(\.id))
            scopedFilters = filters.filter { visibleIDs.contains($0.key) }
        } else {
            scopedFilters = filters
        }
        return BrowseRequest(feedID: feedID, query: feedID == nil ? text : "",
                             filters: scopedFilters, submitted: submittedQuery == text, revision: revision)
    }

    var body: some View {
        VStack(spacing: 0) {
            if adapter.manifest.capabilities.contains(.search) {
                searchField
            }
            sourceTabs
            if let feedError {
                SourceErrorView(message: feedError) { feedRetry += 1 }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if results.isLoading, results.items.isEmpty || results.isStale {
                        ProgressView(results.items.isEmpty ? "Loading manga" : "Updating results")
                            .frame(maxWidth: .infinity)
                    }
                    if let error = results.errorMessage {
                        SourceErrorView(message: error) {
                            if !results.items.isEmpty, !results.isStale, results.nextCursor != nil { pageRequest += 1 }
                            else { revision += 1 }
                        }
                    }
                    if results.isStale {
                        Text("Previous results are shown below.")
                            .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                        if !results.isLoading, results.errorMessage == nil {
                            Button("Reload results") { revision += 1 }
                        }
                    }
                    if !results.isLoading, results.errorMessage == nil, results.items.isEmpty, selectedTab != nil {
                        ContentUnavailableView("No manga found", systemImage: "magnifyingglass",
                                               description: Text("Try another title or change your filters."))
                    }
                    MangaResultsGrid(items: results.items, adapter: adapter, extensions: extensions,
                                     minimumWidth: dynamicTypeSize.isAccessibilitySize ? 180 : 110)
                    if results.nextCursor != nil {
                        Button {
                            pageRequest += 1
                        } label: {
                            HStack {
                                if results.isLoading, !results.isStale { ProgressView() }
                                Text("Load more manga")
                            }
                        }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(results.isLoading || results.isStale || request != loadedRequest)
                    }
                }
                .padding(16)
            }
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.top, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                // SwiftUI may cancel its refresh action when the content changes.
                // The view's request task owns the actual load and inline progress.
                revision += 1
            }
        }
        .onChange(of: query) {
            submittedQuery = nil
            if adapter.manifest.capabilities.contains(.search) { selectedTab = .search }
        }
        .onSubmit {
            submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            searchFocused = false
        }
        .toolbar {
            if adapter.manifest.capabilities.contains(.filters) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label((request?.filters.isEmpty ?? true) ? "Filters" : "Filters (\(request?.filters.count ?? 0))",
                              systemImage: (request?.filters.isEmpty ?? true) ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            SourceFilterSheet(values: filters, scope: request?.feedID == nil ? .search : .feed) {
                if let filterDefinitions { return filterDefinitions }
                let definitions = try await adapter.searchFilters()
                filterDefinitions = definitions
                return definitions
            } apply: { filters = $0 }
        }
        .task(id: feedRetry) {
            do {
                if adapter.manifest.capabilities.contains(.feeds) {
                    feeds = try await adapter.feeds()
                }
                if selectedTab == nil {
                    selectedTab = feeds.first.map { .feed($0.id) } ??
                        (adapter.manifest.capabilities.contains(.search) ? .search : nil)
                }
                feedError = nil
            } catch {
                if !Task.isCancelled {
                    feedError = error.localizedDescription
                    if adapter.manifest.capabilities.contains(.search) { selectedTab = .search }
                }
            }
        }
        .task(id: request) {
            guard let request else { return }
            if let loadedRequest, request.hasSameResults(as: loadedRequest), !results.isStale {
                self.loadedRequest = request
                return
            }
            // The existing grid stays mounted during typing. Only the newest paused query runs.
            if request.feedID == nil, !request.query.isEmpty, !request.submitted {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await load(request)
        }
        .task(id: pageRequest) {
            guard pageRequest > 0, let request, request == loadedRequest else { return }
            await results.loadMore { cursor in
                let current = try await extensions.adapter(for: adapter.connection)
                return try await request.fetch(adapter: current, cursor: cursor)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(MidokuTheme.secondaryText)
            TextField("Search this source", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused($searchFocused)
                .accessibilityLabel("Search this source")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear search")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0)
        .frame(minHeight: 48)
        .background(MidokuTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var sourceTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(feeds) { feed in
                        tab(title: feed.title, selection: .feed(feed.id))
                    }
                    if adapter.manifest.capabilities.contains(.search) {
                        tab(title: "Search", selection: .search)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedTab) {
                if let selectedTab { proxy.scrollTo(selectedTab, anchor: .center) }
            }
        }
    }

    private func tab(title: String, selection: SourceBrowseTab) -> some View {
        Button {
            selectedTab = selection
            searchFocused = selection == .search
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(selectedTab == selection ? MidokuTheme.accentFill : MidokuTheme.surface, in: Capsule())
                .foregroundStyle(selectedTab == selection ? MidokuTheme.onAccent : MidokuTheme.primaryText)
        }
        .buttonStyle(.plain)
        .id(selection)
        .accessibilityAddTraits(selectedTab == selection ? .isSelected : [])
    }

    private func load(_ request: BrowseRequest) async {
        scrollPosition.scrollTo(edge: .top)
        await results.replace {
            let current = try await extensions.adapter(for: adapter.connection)
            return try await request.fetch(adapter: current, cursor: nil)
        }
        if !Task.isCancelled, results.errorMessage == nil { loadedRequest = request }
    }
}

private struct MangaResultsGrid: View {
    let items: [MangaSummary]
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    let minimumWidth: CGFloat

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth, maximum: 240), spacing: 12, alignment: .top)],
                  alignment: .leading, spacing: 20) {
            ForEach(items) { item in
                NavigationLink {
                    SourceEntryView(summary: item, adapter: adapter, extensions: extensions)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        SourceCoverView(url: item.coverURL, adapter: adapter, extensions: extensions)
                            .aspectRatio(2.0 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(item.title).font(.subheadline.weight(.medium))
                            .foregroundStyle(MidokuTheme.primaryText)
                            .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!adapter.manifest.capabilities.contains(.details))
                .accessibilityLabel(item.title)
                .accessibilityHint("Opens manga details and chapters")
            }
        }
    }
}

struct SourceErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message).font(.callout).foregroundStyle(MidokuTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity).padding()
    }
}
