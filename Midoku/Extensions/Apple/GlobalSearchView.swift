import SwiftUI

struct GlobalSearchView: View {
    let extensions: ExtensionEnvironment
    @State private var query = ""
    @State private var submitted = ""
    @State private var revision = 0
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(MidokuTheme.secondaryText)
                TextField("Search all extensions", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($focused)
                    .onSubmit {
                        submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        revision += 1; focused = false
                    }
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
            }.padding(14).background(MidokuTheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(16)
            if submitted.isEmpty {
                ContentUnavailableView("Find your next story", systemImage: "magnifyingglass", description: Text("Enter a title and press Search to search your enabled extensions."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(extensions.connections.filter(\.isEnabled)) { connection in
                            GlobalSearchSection(connection: connection, query: submitted, revision: revision, extensions: extensions)
                        }
                    }.padding(16)
                }
            }
        }.background(MidokuTheme.background).navigationTitle("Global search").navigationBarTitleDisplayMode(.inline)
            .modifier(NativeNavigationBar())
    }
}

private struct GlobalSearchSection: View {
    let connection: SourceConnection
    let query: String
    let revision: Int
    let extensions: ExtensionEnvironment
    @State private var adapter: (any SourceAdapter)?
    @State private var items: [MangaSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var supported = true
    @State private var retry = 0
    var body: some View {
        if supported {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(connection.name).font(.title3.bold())
                    Spacer()
                    NavigationLink("View all") {
                        SourceBrowserView(connection: connection, extensions: extensions,
                            initialSection: HomeSection(connectionID: connection.id, feedID: nil, query: query, filters: [:], sourceTitle: connection.name, title: query))
                    }.font(.subheadline)
                }
                if loading { ProgressView("Searching…") }
                else if let error { SourceErrorView(message: error) { retry += 1 } }
                else if let adapter {
                    if items.isEmpty { Text("No matches").foregroundStyle(MidokuTheme.secondaryText) }
                    else { MangaResultsGrid(items: Array(items.prefix(6)), adapter: adapter, extensions: extensions) }
                }
            }
            .task(id: "\(query)-\(revision)-\(retry)") {
                loading = true; error = nil; items = []
                do {
                    let source = try await extensions.adapter(for: connection)
                    supported = source.manifest.capabilities.contains(.search)
                    guard supported else { loading = false; return }
                    let page = try await source.search(query: query, cursor: nil, filters: [:])
                    try Task.checkCancellation()
                    adapter = source; items = page.items; loading = false
                } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
            }
        }
    }
}
