import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings: AppSettingsStore
    @State private var extensions: ExtensionEnvironment
    @State private var downloads: DownloadManager
    @State private var lock = AppLockController()
    @State private var selectedTab = MidokuTab.home
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var browsePath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var initialized = false
    @State private var loadAttempt = 0

    init() {
        let settings = AppSettingsStore()
        _settings = State(initialValue: settings)
        let extensions = ExtensionEnvironment(settings: settings)
        _extensions = State(initialValue: extensions)
        _downloads = State(initialValue: DownloadManager(extensions: extensions))
    }

    var body: some View {
        Group {
            if initialized {
                tabs
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
        .tint(settings.snapshot.preferences.accent.color)
        .environment(\.midokuAccentFill, settings.snapshot.preferences.accent.fill)
        .environment(settings).environment(lock).environment(downloads)
        .preferredColorScheme(settings.snapshot.preferences.appearance.colorScheme)
        .foregroundStyle(MidokuTheme.primaryText).background(MidokuTheme.background)
        .task(id: loadAttempt) {
            await settings.load()
            guard settings.isReady else { return }
            if !initialized {
                selectedTab = MidokuTab(rawValue: settings.snapshot.preferences.launchTab.rawValue) ?? .home
                lock.configure(enabled: settings.snapshot.preferences.appLock)
                initialized = true
            }
            await extensions.load()
            await downloads.load()
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
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                PinnedHomeView(extensions: extensions) { selectedTab = .browse }
            }.tabItem { Label(MidokuTab.home.title, systemImage: MidokuTab.home.systemImage) }.tag(MidokuTab.home)
            NavigationStack(path: $libraryPath) {
                MidokuEmptyStateView(kind: .library) { selectedTab = .browse }.navigationTitle("Library")
            }.tabItem { Label(MidokuTab.library.title, systemImage: MidokuTab.library.systemImage) }.tag(MidokuTab.library)
            NavigationStack(path: $browsePath) {
                SourceDirectoryView(extensions: extensions)
            }.tabItem { Label(MidokuTab.browse.title, systemImage: MidokuTab.browse.systemImage) }.tag(MidokuTab.browse)
            NavigationStack(path: $historyPath) {
                ReadingHistoryView(extensions: extensions)
            }.tabItem { Label(MidokuTab.history.title, systemImage: MidokuTab.history.systemImage) }.tag(MidokuTab.history)
            NavigationStack(path: $settingsPath) {
                SettingsView(extensions: extensions)
            }.tabItem { Label(MidokuTab.settings.title, systemImage: MidokuTab.settings.systemImage) }.tag(MidokuTab.settings)
        }
        .sheet(item: Binding(get: { extensions.challenges.current }, set: { value in
            if value == nil, let challenge = extensions.challenges.current { extensions.challenges.cancel(id: challenge.id) }
        }), onDismiss: { extensions.challenges.presentationDidDismiss() }) { challenge in
            SourceVerificationView(challenge: challenge, sessions: extensions.browserSessions, coordinator: extensions.challenges)
        }
    }
}

#Preview { ContentView() }
