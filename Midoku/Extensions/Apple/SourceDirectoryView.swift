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
        .navigationTitle("Browse").navigationBarTitleDisplayMode(.inline)
    }
}

