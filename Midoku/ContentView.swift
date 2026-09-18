import SwiftUI

struct ContentView: View {
    @State private var extensions = ExtensionEnvironment()
    @State private var selectedTab = MidokuTab.home
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var browsePath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                MidokuEmptyStateView(kind: .home) {
                    selectedTab = .browse
                }
                .navigationTitle("Home")
            }
            .tabItem { Label(MidokuTab.home.title, systemImage: MidokuTab.home.systemImage) }
            .tag(MidokuTab.home)

            NavigationStack(path: $libraryPath) {
                MidokuEmptyStateView(kind: .library) {
                    selectedTab = .browse
                }
                .navigationTitle("Library")
            }
            .tabItem { Label(MidokuTab.library.title, systemImage: MidokuTab.library.systemImage) }
            .tag(MidokuTab.library)

            NavigationStack(path: $browsePath) {
                SourceDirectoryView(extensions: extensions)
            }
            .tabItem { Label(MidokuTab.browse.title, systemImage: MidokuTab.browse.systemImage) }
            .tag(MidokuTab.browse)

            NavigationStack(path: $historyPath) {
                MidokuEmptyStateView(kind: .history)
                    .navigationTitle("History")
            }
            .tabItem { Label(MidokuTab.history.title, systemImage: MidokuTab.history.systemImage) }
            .tag(MidokuTab.history)

            NavigationStack(path: $settingsPath) {
                List {
                    Section("Your app") {
                        NavigationLink {
                            ExtensionManagementView(extensions: extensions)
                        } label: {
                            Label("Extensions", systemImage: MidokuSymbol.source)
                        }
                        .listRowBackground(MidokuTheme.surface)
                    }
                    #if DEBUG
                    Section("Development") {
                        NavigationLink("Extension Lab") { ExtensionLabView() }
                            .listRowBackground(MidokuTheme.surface)
                    }
                    #endif
                }
                .scrollContentBackground(.hidden)
                .background(MidokuTheme.background)
                .navigationTitle("Settings")
            }
            .tabItem { Label(MidokuTab.settings.title, systemImage: MidokuTab.settings.systemImage) }
            .tag(MidokuTab.settings)
        }
        .tint(MidokuTheme.accent)
        .foregroundStyle(MidokuTheme.primaryText)
        .background(MidokuTheme.background)
        .task { await extensions.load() }
        .sheet(item: Binding(
            get: { extensions.challenges.current },
            set: { value in
                if value == nil, let challenge = extensions.challenges.current {
                    extensions.challenges.cancel(id: challenge.id)
                }
            }
        ), onDismiss: {
            extensions.challenges.presentationDidDismiss()
        }) { challenge in
            SourceVerificationView(
                challenge: challenge, sessions: extensions.browserSessions,
                coordinator: extensions.challenges
            )
        }
    }
}

#Preview {
    ContentView()
}
