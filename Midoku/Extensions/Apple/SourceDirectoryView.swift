import SwiftUI

struct SourceDirectoryView: View {
    let extensions: ExtensionEnvironment

    var body: some View {
        List {
            if extensions.connections.isEmpty {
                ContentUnavailableView {
                    Image(decorative: "MidokuExtensionPlaceholder")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                    Text("Add your sources")
                        .foregroundStyle(MidokuTheme.primaryText)
                } description: {
                    Text("Browse manga from the extensions you add.")
                        .foregroundStyle(MidokuTheme.secondaryText)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(extensions.connections) { connection in
                NavigationLink {
                    SourceSearchView(connection: connection, extensions: extensions)
                } label: {
                    Label {
                        Text(connection.name)
                    } icon: {
                        Image(decorative: "MidokuExtensionPlaceholder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                    }
                }
                .disabled(!connection.isEnabled)
                .listRowBackground(MidokuTheme.surface)
            }
            NavigationLink("Manage extensions") {
                ExtensionManagementView(extensions: extensions)
            }
            .listRowBackground(MidokuTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(MidokuTheme.background)
        .navigationTitle("Browse")
    }
}

private struct SourceSearchView: View {
    let connection: SourceConnection
    let extensions: ExtensionEnvironment
    @State private var query = ""
    @State private var items: [MangaSummary] = []
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading { ProgressView("Searching") }
            if let message { Text(message).foregroundStyle(.secondary) }
            ForEach(items) { item in
                Text(item.title)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MidokuTheme.background)
        .navigationTitle(connection.name)
        .searchable(text: $query, prompt: "Search this source")
        .task(id: query) {
            items = []
            message = nil
            isLoading = false
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                isLoading = true
                let adapter = try await extensions.adapter(for: connection)
                let result = try await adapter.search(query: query, cursor: nil)
                try Task.checkCancellation()
                items = result.items
                message = items.isEmpty ? "No manga found." : nil
                isLoading = false
            } catch is CancellationError {
                // A newer query owns state only when SwiftUI cancelled this task.
                if !Task.isCancelled {
                    message = "Verification cancelled."
                    isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = error.localizedDescription
                isLoading = false
            }
        }
    }
}
