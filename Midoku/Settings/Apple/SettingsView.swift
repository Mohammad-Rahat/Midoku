import SwiftUI
import UIKit

extension AppAppearance {
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
}
extension AppAccent {
    var color: Color {
        let choice = self
        return Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch choice {
            case .forest: return UIColor(red: dark ? 0.61 : 0.216, green: dark ? 0.78 : 0.416, blue: dark ? 0.67 : 0.314, alpha: 1)
            case .slate: return UIColor(red: dark ? 0.67 : 0.27, green: dark ? 0.77 : 0.38, blue: dark ? 0.86 : 0.47, alpha: 1)
            case .ochre: return UIColor(red: dark ? 0.88 : 0.49, green: dark ? 0.74 : 0.34, blue: dark ? 0.50 : 0.17, alpha: 1)
            }
        })
    }
    var fill: Color {
        switch self {
        case .forest: Color(red: 0.216, green: 0.416, blue: 0.314)
        case .slate: Color(red: 0.27, green: 0.38, blue: 0.47)
        case .ochre: Color(red: 0.49, green: 0.34, blue: 0.17)
        }
    }
}
private struct AccentFillKey: EnvironmentKey { static let defaultValue = AppAccent.forest.fill }
extension EnvironmentValues {
    var midokuAccentFill: Color {
        get { self[AccentFillKey.self] }
        set { self[AccentFillKey.self] = newValue }
    }
}

extension AppSettingsStore {
    func binding<Value>(_ path: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { self.snapshot.preferences[keyPath: path] }, set: { value in
            self.update { $0.preferences[keyPath: path] = value }
        })
    }
}

struct SettingsListStyle: ViewModifier {
    var largeTitle = false
    func body(content: Content) -> some View {
        let styled = content.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MidokuTheme.background)
            .foregroundStyle(MidokuTheme.primaryText)
            .environment(\.defaultMinListRowHeight, 52)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(MidokuTheme.background)
        if largeTitle { styled }
        else { styled.modifier(SolidNavigationBar()) }
    }
}
extension View { func settingsStyle(largeTitle: Bool = false) -> some View { modifier(SettingsListStyle(largeTitle: largeTitle)) } }

struct SettingLabel: View {
    let title: String
    let symbol: String
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.medium))
                .foregroundStyle(.tint).frame(width: 30, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
            }
            .padding(.vertical, 4)
        }
    }
}

struct SettingPicker<Choice: SettingChoice>: View {
    let title: String
    @Binding var selection: Choice
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(Choice.allCases), id: \.rawValue) { item in Text(item.title).tag(item) }
        }
    }
}

struct SettingsView: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section("Personalize") {
                NavigationLink { AppearanceSettingsView() } label: {
                    SettingLabel(title: "Appearance", symbol: "circle.lefthalf.filled", detail: settings.snapshot.preferences.appearance.title)
                }
                NavigationLink { HomeSectionsSettingsView() } label: {
                    SettingLabel(title: "Home sections", symbol: "rectangle.stack", detail: "\(settings.snapshot.homeSections.count) saved sections")
                }
                NavigationLink { LibrarySettingsView() } label: {
                    SettingLabel(title: "Library", symbol: "books.vertical", detail: "Categories and display preferences")
                }
                NavigationLink { ReaderSettingsView() } label: {
                    SettingLabel(title: "Reader preferences", symbol: "book.pages", detail: settings.snapshot.preferences.reader.mode.title)
                }
            }.listRowBackground(MidokuTheme.surface)
            Section("Your app") {
                NavigationLink { PrivacySettingsView() } label: {
                    SettingLabel(title: "Privacy & app lock", symbol: "lock", detail: settings.snapshot.preferences.appLock ? "App lock is on" : "History and privacy controls")
                }
                NavigationLink { ExtensionManagementView(extensions: extensions) } label: {
                    SettingLabel(title: "Extensions", symbol: "square.grid.2x2", detail: "\(extensions.connections.count) source connections")
                }
                NavigationLink { StorageSettingsView(extensions: extensions) } label: {
                    SettingLabel(title: "Downloads & storage", symbol: "arrow.down.circle", detail: "Downloads, cover cache, and storage")
                }
                NavigationLink { BackupSettingsView(extensions: extensions) } label: {
                    SettingLabel(title: "Backup & restore", symbol: "externaldrive")
                }
            }.listRowBackground(MidokuTheme.surface)
            Section {
                NavigationLink { AboutSettingsView(extensions: extensions) } label: {
                    SettingLabel(title: "About Midoku", symbol: "info.circle", detail: AppBuild.displayVersion)
                }
            }.listRowBackground(MidokuTheme.surface)
            #if DEBUG
            Section("Development") {
                NavigationLink("Extension Lab") { ExtensionLabView() }
            }.listRowBackground(MidokuTheme.surface)
            #endif
            Color.clear.frame(height: 1).id("settings-end").listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .settingsStyle(largeTitle: true).contentMargins(.top, 0, for: .scrollContent).mainScreenHeader("Settings")
        #if DEBUG
        .task {
            if CommandLine.arguments.contains("--settings-bottom-preview") {
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo("settings-end", anchor: .bottom)
            }
        }
        #endif
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        Form {
            Section("Theme") {
                SettingPicker(title: "Appearance", selection: settings.binding(\.appearance))
                SettingPicker(title: "Accent", selection: settings.binding(\.accent))
                HStack(spacing: 16) {
                    ForEach(AppAccent.allCases) { accent in
                        Button { settings.update { $0.preferences.accent = accent } } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(accent.fill).frame(width: 40, height: 40)
                                    if settings.snapshot.preferences.accent == accent {
                                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                    }
                                }
                                Text(accent.title).font(.caption).foregroundStyle(MidokuTheme.primaryText)
                            }.frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accent.title)
                        .accessibilityAddTraits(settings.snapshot.preferences.accent == accent ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            }.listRowBackground(MidokuTheme.surface)
            Section {
                SettingPicker(title: "Browse cover density", selection: settings.binding(\.coverDensity))
                NavigationLink("Library layout") { LibrarySettingsView() }
                SettingPicker(title: "Open on launch", selection: settings.binding(\.launchTab))
            } header: { Text("Layout") } footer: {
                Text("Browse cover density applies to source grids. Library has its own layout settings. Larger accessibility text keeps covers and labels comfortably spaced. Your launch tab is used the next time Midoku opens.")
            }.listRowBackground(MidokuTheme.surface)
            Section("Preview") {
                HStack(spacing: 12) {
                    Image("MidokuCoverPlaceholder").resizable().scaledToFit().frame(width: 56, height: 84)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little time to read").font(.headline)
                        Text("Your colors, everywhere.").font(.subheadline).foregroundStyle(MidokuTheme.secondaryText)
                        Label("Selected accent", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.tint)
                    }
                }.padding(.vertical, 8)
            }.listRowBackground(MidokuTheme.surface)
        }.settingsStyle().navigationTitle("Appearance")
    }
}

struct LibrarySettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    var body: some View {
        Form {
            LibraryLayoutSection()
            Section {
                NavigationLink { CategoriesSettingsView() } label: {
                    SettingLabel(title: "Categories", symbol: "folder", detail: "\(settings.snapshot.categories.count) categories")
                }
            }.listRowBackground(MidokuTheme.surface)
            Section {
                SettingPicker(title: "Default sort", selection: settings.binding(\.librarySort))
                Toggle("Refresh when opening the app", isOn: settings.binding(\.refreshOnLaunch))
            } header: { Text("Library defaults") } footer: {
                Text("Sort your library and check followed sources when opening the app. Pull to refresh for an immediate check.")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Toggle("Show chapter thumbnails", isOn: settings.binding(\.chapterThumbnails))
            } header: { Text("Chapter lists") } footer: {
                Text("Chapter thumbnails use the first page, or your custom chapter cover. Previews load as chapters become visible and are cached on this device.")
            }.listRowBackground(MidokuTheme.surface)
        }.settingsStyle().navigationTitle("Library")
    }
}

struct ReaderSettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    var body: some View {
        Form {
            Section("Reading mode") {
                ForEach(ReaderMode.allCases) { mode in
                    Button { settings.update { $0.preferences.reader.mode = mode } } label: {
                        HStack {
                            Label(mode.title, systemImage: mode == .continuous ? "arrow.down" : (mode == .rightToLeft ? "arrow.left" : "arrow.right"))
                                .foregroundStyle(MidokuTheme.primaryText)
                            Spacer()
                            if settings.snapshot.preferences.reader.mode == mode {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(settings.snapshot.preferences.reader.mode == mode ? .isSelected : [])
                }
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Toggle("Tap to navigate", isOn: settings.binding(\.reader.tapNavigation))
                SettingPicker(title: "Tap zones", selection: settings.binding(\.reader.tapZones))
                    .disabled(!settings.snapshot.preferences.reader.tapNavigation)
                SettingPicker(title: "Image scaling", selection: settings.binding(\.reader.fit))
                SettingPicker(title: "Orientation", selection: settings.binding(\.reader.orientation))
                SettingPicker(title: "Background", selection: settings.binding(\.reader.background))
                Toggle("Keep screen awake", isOn: settings.binding(\.reader.keepAwake))
            } header: { Text("Navigation & display") } footer: {
                Text("Tap the center to show or hide controls. Edge taps follow the reading direction; continuous reading always scrolls down. Zoomed pages can be panned without turning a page.")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Toggle("Use reader brightness", isOn: settings.binding(\.reader.customBrightness))
                if settings.snapshot.preferences.reader.customBrightness {
                    LabeledContent("Brightness", value: "\(Int(settings.snapshot.preferences.reader.brightness * 100))%")
                    Slider(value: settings.binding(\.reader.brightness), in: 0.05...1)
                        .accessibilityLabel("Reader brightness")
                }
            } header: { Text("Brightness") } footer: {
                Text("Your previous screen brightness is restored when you leave the reader or switch away from Midoku.")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Text("These are your global defaults. Use Edit details on an entry to set its own reader preferences.")
                    .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
            }.listRowBackground(Color.clear)
        }.settingsStyle().navigationTitle("Reader preferences")
    }
}

struct PrivacySettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(AppLockController.self) private var lock
    @State private var clearHistory = false
    var body: some View {
        Form {
            Section {
                Toggle("App lock", isOn: Binding(get: { settings.snapshot.preferences.appLock }, set: { value in
                    Task { await lock.changeEnabled(value, settings: settings) }
                })).disabled(lock.authenticating)
                SettingPicker(title: "Lock after leaving", selection: settings.binding(\.lockDelay))
                    .disabled(!settings.snapshot.preferences.appLock)
                if let message = lock.message { Text(message).font(.footnote).foregroundStyle(MidokuTheme.secondaryText) }
            } header: { Text("Device authentication") } footer: {
                Text("Use Face ID, Touch ID, or your device passcode. App lock protects access inside Midoku; it does not separately encrypt your library.")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Toggle("Hide in app switcher", isOn: settings.binding(\.protectAppSwitcher))
                    .disabled(settings.snapshot.preferences.appLock)
                if settings.snapshot.preferences.appLock {
                    Text("Content is always hidden outside the app while app lock is enabled.")
                        .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                }
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Toggle("Record reading history", isOn: settings.binding(\.recordHistory))
                LabeledContent("Recent chapters", value: "\(settings.snapshot.history.count) of 100")
                Button("Clear reading history", role: .destructive) { clearHistory = true }
                    .disabled(settings.snapshot.history.isEmpty)
            } header: { Text("History") } footer: {
                Text("Turning off history stops new entries. Clearing history leaves reading progress and saved chapters intact.")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Text("Your settings and reading activity stay on this device. Midoku has no analytics or advertising SDK. Manga sources receive the requests you make to them.")
                    .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
            }.listRowBackground(Color.clear)
        }.settingsStyle().navigationTitle("Privacy & app lock")
            .confirmationDialog("Clear reading history?", isPresented: $clearHistory, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { settings.update { $0.history.removeAll() } }
            } message: { Text("This removes all recent chapters from History. Your reading position is kept.") }
    }
}

nonisolated enum AppBuild {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static var displayVersion: String { "Version \(version) (\(build))" }
}
