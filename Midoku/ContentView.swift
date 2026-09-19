import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings: AppSettingsStore
    @State private var extensions: ExtensionEnvironment
    @State private var library: LibraryCoordinator
    @State private var downloads: DownloadManager
    @State private var lock = AppLockController()
    @State private var selectedTab = MidokuTab.home
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var browsePath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var hiddenBars: [MidokuTab: Bool] = [:]
    @State private var initialized = false
    @State private var gridLandscape = false
    @State private var loadAttempt = 0

    init() {
        let settings: AppSettingsStore
        #if DEBUG
        if CommandLine.arguments.contains("--library-preview") {
            settings = AppSettingsStore(root: URL.applicationSupportDirectory.appending(path: "Midoku-UIPreview", directoryHint: .isDirectory))
        } else { settings = AppSettingsStore() }
        #else
        settings = AppSettingsStore()
        #endif
        _settings = State(initialValue: settings)
        let extensions = ExtensionEnvironment(settings: settings)
        _extensions = State(initialValue: extensions)
        _library = State(initialValue: LibraryCoordinator(settings: settings, extensions: extensions))
        _downloads = State(initialValue: DownloadManager(extensions: extensions))
    }

    var body: some View {
        Group {
            if initialized {
                Group {
                    #if DEBUG
                    if CommandLine.arguments.contains("--reader-preview") || CommandLine.arguments.contains("--fullscreen-preview") {
                        NavigationStack { ReaderChromePreview() }
                    } else { tabs }
                    #else
                    tabs
                    #endif
                }
                    .allowsHitTesting(!lock.state.isLocked && !settings.isRestoring)
                    .accessibilityHidden(lock.state.isLocked)
                    .overlay { if lock.state.isLocked { AppLockView(lock: lock) } }
            } else if let error = settings.loadError {
                VStack(spacing: 20) {
                    ContentUnavailableView("Saved data needs attention", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text(error))
                    Button("Try again") { loadAttempt += 1 }.buttonStyle(.borderedProminent)
                }
            } else { MidokuSplashView() }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { gridLandscape = $0 }
        .environment(\.gridLandscape, gridLandscape)
        .tint(settings.snapshot.preferences.accent.color)
        .environment(\.midokuAccentFill, settings.snapshot.preferences.accent.fill)
        .environment(settings).environment(lock).environment(downloads).environment(library)
        .preferredColorScheme(settings.snapshot.preferences.appearance.colorScheme)
        .foregroundStyle(MidokuTheme.primaryText).background(MidokuTheme.background)
        .task(id: loadAttempt) {
            await settings.load()
            guard settings.isReady else { return }
            // Finish the local adapter catalogue before any screen requests a feed or cover.
            await extensions.load()
            if !initialized {
                selectedTab = MidokuTab(rawValue: settings.snapshot.preferences.launchTab.rawValue) ?? .home
                lock.configure(enabled: settings.snapshot.preferences.appLock)
                initialized = true
            }
            #if DEBUG
            if CommandLine.arguments.contains("--library-preview") {
                do {
                    let id = try await LibraryPreviewData.prepare(settings)
                    try await settings.commit { snapshot in
                        let gridPreview = ["--chapter-grid-preview", "--chapter-compact-preview", "--chapter-thumbnail-preview", "--layout-preview", "--chapter-settings-preview"].contains(where: CommandLine.arguments.contains)
                        snapshot.preferences.chapterLayout = ChapterLayoutPreferences(style: gridPreview ? .grid : .list,
                            gridStyle: CommandLine.arguments.contains("--chapter-compact-preview") ? .compact :
                                (CommandLine.arguments.contains("--chapter-thumbnail-preview") ? .thumbnail : .standard))
                        if CommandLine.arguments.contains("--empty-clipboard-preview") { snapshot.library.clipboard = [] }
                    }
                    if CommandLine.arguments.contains("--home-preview") { selectedTab = .home }
                    else if CommandLine.arguments.contains("--browse-preview") || CommandLine.arguments.contains("--search-preview") || CommandLine.arguments.contains("--source-grid-preview") { selectedTab = .browse }
                    else if CommandLine.arguments.contains("--history-preview") { selectedTab = .history }
                    else if CommandLine.arguments.contains("--settings-preview") || CommandLine.arguments.contains("--settings-bottom-preview") || (CommandLine.arguments.contains("--layout-preview") || CommandLine.arguments.contains("--chapter-settings-preview")) { selectedTab = .settings }
                    else { selectedTab = .library }
                        if ["--entry-preview", "--rename-preview", "--chapters-preview", "--chapter-grid-preview", "--chapter-compact-preview", "--chapter-thumbnail-preview", "--empty-clipboard-preview"].contains(where: CommandLine.arguments.contains), libraryPath.isEmpty { libraryPath.append(id) }
                } catch { settings.update { _ in throw error } }
            }
            #endif
            await downloads.load()
            if settings.snapshot.preferences.refreshOnLaunch { await library.refresh(automatic: true) }
        }
        .onChange(of: scenePhase) {
            guard initialized else { return }
            lock.sceneChanged(scenePhase, preferences: settings.snapshot.preferences)
            downloads.setActive(scenePhase == .active)
        }
        .onChange(of: settings.snapshot.preferences.wifiOnlyDownloads) { downloads.conditionsChanged() }
        .onChange(of: settings.restoreGeneration) {
            homePath = NavigationPath(); libraryPath = NavigationPath(); browsePath = NavigationPath()
            historyPath = NavigationPath(); settingsPath = NavigationPath()
        }
        .safeAreaInset(edge: .top) {
            if let error = settings.saveError, !lock.state.isLocked {
                HStack {
                    Text(error).font(.caption)
                    Button("Retry") { Task { try? await settings.flush() } }
                }.padding().background(MidokuTheme.elevated)
            }
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
        TabView(selection: $selectedTab) {
            ForEach(MidokuTab.allCases) { tab in
                tabContent(tab)
                    .tag(tab)
                    .toolbar(.hidden, for: .tabBar)
                    .onPreferenceChange(AppTabBarHiddenPreference.self) { hiddenBars[tab] = $0 }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if hiddenBars[selectedTab] != true { TraditionalTabBar(selection: $selectedTab) }
        }
        .background(MidokuTheme.background)
        .sheet(item: Binding(get: { extensions.challenges.current }, set: { value in
            if value == nil, let challenge = extensions.challenges.current { extensions.challenges.cancel(id: challenge.id) }
        }), onDismiss: { extensions.challenges.presentationDidDismiss() }) { challenge in
            SourceVerificationView(challenge: challenge, sessions: extensions.browserSessions, coordinator: extensions.challenges)
        }
    }
    @ViewBuilder private func tabContent(_ tab: MidokuTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: $homePath) {
                PinnedHomeView(extensions: extensions) { selectedTab = .browse }
            }
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryView(extensions: extensions) { selectedTab = .browse }
                    .navigationDestination(for: UUID.self) { LibraryEntryView(entryID: $0, extensions: extensions) }
            }
        case .browse:
            NavigationStack(path: $browsePath) {
                #if DEBUG
                if CommandLine.arguments.contains("--search-preview") { GlobalSearchView(extensions: extensions) }
                else if CommandLine.arguments.contains("--source-grid-preview") { SourceGridPreview(extensions: extensions) }
                else { SourceDirectoryView(extensions: extensions, isRoot: true) }
                #else
                SourceDirectoryView(extensions: extensions, isRoot: true)
                #endif
            }
        case .history:
            NavigationStack(path: $historyPath) { ReadingHistoryView(extensions: extensions) }
        case .settings:
            NavigationStack(path: $settingsPath) {
                #if DEBUG
                if (CommandLine.arguments.contains("--layout-preview") || CommandLine.arguments.contains("--chapter-settings-preview")) { LibrarySettingsView() }
                else { SettingsView(extensions: extensions) }
                #else
                SettingsView(extensions: extensions)
                #endif
            }
        }
    }
}

#Preview { ContentView() }
