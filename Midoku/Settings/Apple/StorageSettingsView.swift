import SwiftUI

actor AppStorageMaintenance {
    struct Usage: Sendable { let appData: Int64; let cache: Int64 }
    private let cache = URL.cachesDirectory.appending(path: "Midoku", directoryHint: .isDirectory)
    private let support = URL.applicationSupportDirectory.appending(path: "Midoku", directoryHint: .isDirectory)
    func usage() throws -> Usage { Usage(appData: try bytes(support, excludingDownloads: true), cache: try bytes(cache)) }
    func clearCache() throws {
        if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
    }
    private func bytes(_ root: URL, excludingDownloads: Bool = false) throws -> Int64 {
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]) else { return 0 }
        var count: Int64 = 0
        for case let url as URL in iterator {
            if excludingDownloads && url.lastPathComponent == "Downloads" { iterator.skipDescendants(); continue }
            let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if resource.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if resource.isRegularFile == true { count += Int64(resource.fileSize ?? 0) }
        }
        return count
    }
}

struct StorageSettingsView: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    @State private var usage: AppStorageMaintenance.Usage?
    @State private var downloadBytes: Int64 = 0
    @State private var clearCache = false
    @State private var clearDownloads = false
    @State private var busy = false
    @State private var message: String?
    private let maintenance = AppStorageMaintenance()
    var body: some View {
        Form {
            Section {
                NavigationLink { DownloadsListView() } label: {
                    SettingLabel(title: "Downloads", symbol: "arrow.down.circle", detail: "\(downloads.items.filter { $0.status == .completed }.count) saved chapters")
                }
                Toggle("Download on Wi-Fi only", isOn: settings.binding(\.wifiOnlyDownloads))
            } header: { Text("Offline reading") } footer: {
                Text("Download a chapter from its menu in Browse. Keep Midoku open while downloading. Paused or interrupted jobs can be resumed from the queue.")
            }.listRowBackground(MidokuTheme.surface)
            Section("On this device") {
                LabeledContent("App data & recovery copies", value: usage.map { format($0.appData) } ?? "Calculating…")
                LabeledContent("Downloads & partial files", value: format(downloadBytes))
                LabeledContent("Temporary disk cache", value: usage.map { format($0.cache) } ?? "Calculating…")
                LabeledContent("Image memory limit", value: "64 MB")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Button("Clear cache") { clearCache = true }.disabled(busy)
                Button("Delete saved & paused downloads", role: .destructive) { clearDownloads = true }
                    .disabled(busy || downloads.items.filter { [.completed, .paused, .failed, .cancelled].contains($0.status) }.isEmpty)
            } footer: {
                Text("Clearing cache keeps downloaded pages, reading progress, categories, Home sections, custom assets, and website sessions. Removing downloads keeps reading progress and History.")
            }.listRowBackground(MidokuTheme.surface)
            if busy { ProgressView("Updating storage").listRowBackground(MidokuTheme.surface) }
            if let message { Text(message).font(.footnote).listRowBackground(MidokuTheme.surface) }
        }.settingsStyle().navigationTitle("Downloads & storage")
            .task { await refresh() }
            .onChange(of: settings.snapshot.preferences.wifiOnlyDownloads) { downloads.conditionsChanged() }
            .confirmationDialog("Clear temporary cache?", isPresented: $clearCache, titleVisibility: .visible) {
                Button("Clear cache") {
                    Task {
                        busy = true
                        do {
                            try await maintenance.clearCache()
                            await extensions.images.clear()
                            message = "Cache cleared. Saved chapters and reading data were kept."
                        } catch { message = "Some cache files could not be removed. Your reading data was kept." }
                        await refresh(); busy = false
                    }
                }
            } message: { Text("Covers and online pages may need to load again.") }
            .confirmationDialog("Delete downloaded files?", isPresented: $clearDownloads, titleVisibility: .visible) {
                Button("Delete downloads", role: .destructive) {
                    Task { busy = true; await downloads.clearFinishedFiles(); await refresh(); busy = false }
                }
            } message: { Text("Saved chapters and paused/failed partial files will be removed. Active and queued jobs are kept. Reading progress is not deleted.") }
    }
    private func refresh() async {
        do { usage = try await maintenance.usage(); downloadBytes = try await downloads.storage.totalBytes() }
        catch { message = "Storage totals could not be read. Try opening this screen again." }
    }
    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct DownloadsListView: View {
    @Environment(DownloadManager.self) private var downloads
    @State private var deleting: SavedDownload?
    var body: some View {
        List {
            if let error = downloads.error {
                Text(error).font(.callout).foregroundStyle(MidokuTheme.danger)
                if downloads.isReady { Button("Retry saving queue") { Task { await downloads.retrySave() } } }
            }
            if downloads.waitingForWiFi && downloads.items.contains(where: { $0.status == .queued }) {
                Label("Waiting for Wi-Fi", systemImage: "wifi").font(.callout)
            } else if !downloads.connected && downloads.items.contains(where: { $0.status == .queued }) {
                Label("Waiting for a connection", systemImage: "wifi.slash").font(.callout)
            }
            if !downloads.isReady && downloads.error == nil { ProgressView("Checking saved downloads") }
            if downloads.isReady && downloads.items.isEmpty {
                ContentUnavailableView("Take a story with you", systemImage: "arrow.down.circle",
                    description: Text("Open a chapter menu in Browse and choose Download chapter."))
                    .listRowBackground(Color.clear)
            }
            ForEach(downloads.items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.record.mangaTitle).font(.headline)
                    Text((item.record.chapter.number.map { "Chapter \($0) · " } ?? "") + item.record.sourceName)
                        .font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                    if item.status == .completed {
                        NavigationLink("Read offline") { OfflineChapterReader(download: item) }
                    } else {
                        Text(item.message ?? item.status.title).font(.subheadline).foregroundStyle(MidokuTheme.secondaryText)
                        if item.expectedPages > 0 {
                            ProgressView(value: Double(item.pages.count), total: Double(item.expectedPages))
                            Text("\(item.pages.count) of \(item.expectedPages) pages").font(.caption)
                        }
                    }
                    HStack(spacing: 20) {
                        if [.queued, .resolving, .downloading].contains(item.status) {
                            Button("Pause") { Task { await downloads.pause(item.id) } }
                            Button("Cancel", role: .destructive) { Task { await downloads.cancel(item.id) } }
                        } else if [.paused, .failed, .cancelled].contains(item.status) {
                            Button(item.status == .failed ? "Retry" : "Resume") { Task { await downloads.resume(item.id) } }
                        }
                        if ![.resolving, .downloading].contains(item.status) {
                            Button("Delete", role: .destructive) { deleting = item }
                        }
                    }.buttonStyle(.borderless).frame(minHeight: 44)
                }.padding(.vertical, 8).listRowBackground(MidokuTheme.surface)
            }
        }.settingsStyle().navigationTitle("Downloads")
            .confirmationDialog("Delete this download?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete download", role: .destructive) {
                    if let deleting { Task { await downloads.delete(deleting.id) } }
                    deleting = nil
                }
            } message: { Text("The saved pages will be removed. Reading progress and History are kept.") }
    }
}

struct OfflineChapterReader: View {
    let download: SavedDownload
    @Environment(DownloadManager.self) private var downloads
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.scenePhase) private var phase
    @State private var restoreGeneration: UUID?
    @State private var selected = 0
    @State private var device = ReaderDeviceController()
    @State private var showPreferences = false
    private var preferences: ReaderPreferences { settings.snapshot.preferences.reader }
    var body: some View {
        VStack(spacing: 0) {
            Text("\(download.record.sourceName) · Saved on this device")
                .font(.caption).foregroundStyle(MidokuTheme.secondaryText).padding(10)
            GeometryReader { geometry in
                if preferences.mode == .continuous {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(download.pages.enumerated()), id: \.offset) { index, page in
                                    image(page, index: index, size: geometry.size, continuous: true).id(index)
                                        .onScrollVisibilityChange(threshold: 0.5) { visible in if visible { selected = index } }
                                }
                            }
                        }.onAppear { proxy.scrollTo(selected, anchor: .top) }
                    }
                } else if download.pages.indices.contains(selected) {
                    image(download.pages[selected], index: selected, size: geometry.size, continuous: false).id(selected)
                }
            }
            HStack {
                Button("Previous") { selected = max(0, selected - 1) }.disabled(selected == 0 || preferences.mode == .continuous)
                Spacer()
                Text("\(selected + 1) / \(download.pages.count)").monospacedDigit()
                Spacer()
                Button("Next") { selected = min(download.pages.count - 1, selected + 1) }
                    .disabled(selected + 1 >= download.pages.count || preferences.mode == .continuous)
            }.padding().background(MidokuTheme.surface)
        }
        .background(preferences.background == .black ? Color.black : (preferences.background == .paper ? Color.white : MidokuTheme.background))
        .navigationTitle(download.record.mangaTitle).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .toolbar { Button { showPreferences = true } label: { Label("Reader preferences", systemImage: "slider.horizontal.3") } }
        .sheet(isPresented: $showPreferences) {
            NavigationStack { ReaderSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreferences = false } } } }
        }
        .onAppear {
            restoreGeneration = settings.restoreGeneration
            if let position = settings.snapshot.progress.first(where: { $0.id == download.record.id }) {
                selected = download.pages.firstIndex(where: { $0.id == position.pageID }) ?? min(position.pageIndex, max(0, download.pages.count - 1))
            }
            // A retained offline chapter may outlive a removed source after Replace restore.
            if settings.snapshot.connections.contains(where: { $0.id == download.record.identity.listing.connectionID }) {
                var record = download.record; record.openedAt = Date()
                settings.update { $0.opened(record) }
            }
            device.begin(preferences)
        }
        .onChange(of: selected) { save() }
        .onChange(of: preferences) { device.apply(preferences) }
        .onChange(of: phase) { if phase == .active { device.apply(preferences) } else { save(); device.suspend() } }
        .onDisappear { save(); device.end() }
    }
    private func image(_ page: DownloadPage, index: Int, size: CGSize, continuous: Bool) -> some View {
        ReaderPageImage(index: index, viewport: size, preferences: preferences, continuous: continuous,
            tap: { fraction in
                let delta = preferences.tapNavigation ? preferences.tapZones.action(at: fraction, mode: preferences.mode) : 0
                selected = max(0, min(download.pages.count - 1, selected + delta))
            }, loaded: {}, imageLoader: { try await downloads.image(page: page, chapterID: download.id) },
            swipe: { delta in selected = max(0, min(download.pages.count - 1, selected + delta)) })
    }
    private func save() {
        guard restoreGeneration == settings.restoreGeneration, download.pages.indices.contains(selected), settings.snapshot.connections.contains(where: { $0.id == download.record.identity.listing.connectionID }) else { return }
        settings.savePosition(ReadingPosition(identity: download.record.identity, pageID: download.pages[selected].id,
            pageIndex: selected, pageCount: download.pages.count, fraction: 0, updatedAt: Date()))
    }
}

struct ChapterReaderDestination: View {
    let mangaID: String
    let mangaTitle: String
    let chapter: ChapterRecord
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @Environment(DownloadManager.self) private var downloads
    private var identity: SourceChapterIdentity {
        SourceChapterIdentity(listing: SourceListingIdentity(connectionID: adapter.connection.id, externalID: mangaID), externalID: chapter.id)
    }
    var body: some View {
        if let download = downloads.items.first(where: { $0.record.id == identity && $0.status == .completed }) {
            OfflineChapterReader(download: download)
        } else {
            SourceChapterReader(mangaID: mangaID, mangaTitle: mangaTitle, chapter: chapter, adapter: adapter, extensions: extensions)
        }
    }
}
