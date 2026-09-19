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
                    SourceBrowserView(connection: connection, extensions: extensions)
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
        .contentMargins(.top, 0, for: .scrollContent)
        .mainScreenHeader("Browse") {
            NavigationLink { GlobalSearchView(extensions: extensions) } label: {
                Label("Search all extensions", systemImage: "magnifyingglass").frame(width: 44, height: 44)
            }
            NavigationLink { ExtensionManagementView(extensions: extensions) } label: {
                Label("Manage extensions", systemImage: "plus").frame(width: 44, height: 44)
            }
        }
    }
}

