import SwiftUI
import UniformTypeIdentifiers

extension UTType { static let midokuBackup = UTType(exportedAs: "dev.midoku.settings-backup", conformingTo: .json) }

struct MidokuExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.midokuBackup, .json, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= BackupArchive.maximumBytes else { throw SettingsFailure.tooLarge }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupPreview: Identifiable {
    let id = UUID()
    let archive: BackupArchive
    let snapshot: AppSnapshot
}

struct BackupSettingsView: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @State private var importing = false
    @State private var exporting = false
    @State private var document: MidokuExportDocument?
    @State private var preview: BackupPreview?
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Label("Keep a copy of your reading setup", systemImage: "externaldrive.badge.checkmark")
                    .font(.headline).padding(.vertical, 8)
                Text("Includes your library, chapter arrangements, local edits and covers, clipboard, preferences, categories, Home sections, reading positions, History, and source connections. Your export contains private reading information and is not password protected.")
                    .font(.callout).foregroundStyle(MidokuTheme.secondaryText)
            }.listRowBackground(MidokuTheme.surface)
            Section {
                Button { export() } label: { Label("Export backup", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                if busy { ProgressView("Preparing backup") }
            } footer: {
                Text("Offline pages, cache, sign-in sessions, device lock enrollment, and executable extensions are excluded.")
            }.listRowBackground(MidokuTheme.surface).disabled(busy || settings.isRestoring)
            Section {
                NavigationLink { RecoveryBackupsView(extensions: extensions) } label: {
                    SettingLabel(title: "Recovery copies", symbol: "clock.arrow.circlepath", detail: "Created before each restore")
                }
            }.listRowBackground(MidokuTheme.surface)
            if let message { Section { Text(message).font(.callout) }.listRowBackground(MidokuTheme.surface) }
        }.settingsStyle().navigationTitle("Backup & restore")
            .fileExporter(isPresented: $exporting, document: document, contentType: .midokuBackup,
                          defaultFilename: "Midoku-\(Date().formatted(.iso8601.year().month().day()))") { result in
                switch result {
                case .success: message = "Backup saved."
                case .failure: message = "The backup could not be saved. You can try again."
                }
                document = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.midokuBackup, .json, .data]) { result in
                switch result {
                case .success(let url): validate(url)
                case .failure: message = "No backup was imported."
                }
            }
            .sheet(item: $preview) { preview in RestorePreviewView(preview: preview, extensions: extensions) }
    }
    private func export() {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                try await settings.flush()
                let snapshot = settings.snapshot
                let manifests = extensions.available
                let version = AppBuild.displayVersion
                let data = try await Task.detached {
                    try BackupArchive(snapshot: snapshot, extensions: manifests, appVersion: version).encoded()
                }.value
                _ = try BackupArchive.decode(data)
                document = MidokuExportDocument(data: data); exporting = true
            } catch { message = (error as? SettingsFailure)?.localizedDescription ?? "The backup could not be prepared. Check available storage and try again." }
        }
    }
    private func validate(_ url: URL) {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let result = try await BackupFileReader.read(url)
                preview = BackupPreview(archive: result.0, snapshot: result.1)
            } catch { message = (error as? SettingsFailure)?.localizedDescription ?? "This file could not be opened. Choose a complete Midoku backup." }
        }
    }
}

nonisolated enum BackupFileReader {
    static func read(_ url: URL) async throws -> (BackupArchive, AppSnapshot) {
        try await Task.detached {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw SettingsFailure.invalidBackup }
            guard let size = values.fileSize, size <= BackupArchive.maximumBytes else { throw SettingsFailure.tooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: BackupArchive.maximumBytes + 1) ?? Data()
            return try BackupArchive.decode(data)
        }.value
    }
}

struct RestorePreviewView: View {
    @Environment(DownloadManager.self) private var downloads
    let preview: BackupPreview
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var merge = true
    @State private var confirming = false
    @State private var busy = false
    @State private var message: String?
    private var missing: [String] {
        let available = Set(extensions.available.map(\.id))
        return Array(Set(preview.snapshot.connections.map(\.extensionID))).filter { !available.contains($0) }.sorted()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Backup contents") {
                    LabeledContent("Created", value: preview.archive.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Source connections", value: "\(preview.archive.counts.sources)")
                    LabeledContent("Categories", value: "\(preview.archive.counts.categories)")
                    LabeledContent("Home sections", value: "\(preview.archive.counts.homeSections)")
                    LabeledContent("Reading positions", value: "\(preview.archive.counts.progress)")
                    LabeledContent("History records", value: "\(preview.archive.counts.history)")
                    LabeledContent("Library entries / chapters", value: "\(preview.archive.counts.libraryEntries ?? 0) / \(preview.archive.counts.chapters ?? 0)")
                    LabeledContent("Custom covers", value: "\(preview.archive.counts.covers ?? 0)")
                }.listRowBackground(MidokuTheme.surface)
                Section {
                    Picker("Restore method", selection: $merge) { Text("Merge").tag(true); Text("Replace").tag(false) }
                        .pickerStyle(.segmented)
                    Text(merge ? "Add missing records. Keep your current entries, edits, preferences, category names, Home order, and reading positions when records conflict. History keeps the newest visit to each chapter, up to 100."
                         : "Replace the library, chapter arrangements, covers, preferences, categories, Home sections, History, reading positions, and source connections with this backup. Offline downloads, the source identities they require, and your current device lock are kept.")
                        .font(.callout).foregroundStyle(MidokuTheme.secondaryText)
                } header: { Text("Choose how to restore") } footer: {
                    Text("A local recovery copy is saved before any change. Sign-in sessions are never imported. Existing local source sessions stay on this device.")
                }.listRowBackground(MidokuTheme.surface)
                if !missing.isEmpty {
                    Section("Missing extensions") {
                        ForEach(missing, id: \.self) { Text($0).font(.footnote) }
                        Text("These references will be kept. They need a compatible bundled extension before reading is available.").font(.footnote)
                    }.listRowBackground(MidokuTheme.surface)
                }
                if let message { Section { Text(message).foregroundStyle(MidokuTheme.danger) }.listRowBackground(MidokuTheme.surface) }
                Section {
                    Button(merge ? "Merge backup" : "Replace with backup", role: merge ? nil : .destructive) { confirming = true }
                    if busy { ProgressView("Restoring") }
                }.listRowBackground(MidokuTheme.surface)
            }.settingsStyle().navigationTitle("Review backup").disabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }.sharedBackgroundVisibility(.hidden) }
                .interactiveDismissDisabled(busy)
                .confirmationDialog(merge ? "Merge this backup?" : "Replace your current setup?", isPresented: $confirming, titleVisibility: .visible) {
                    Button(merge ? "Merge" : "Replace", role: merge ? nil : .destructive) { restore() }
                } message: { Text("Midoku will first create a recovery copy. Your current app lock and offline downloads are preserved.") }
        }
    }
    private func restore() {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                // A newly restored connection must not inherit a leftover browser profile with the same UUID.
                let localIDs = Set(settings.snapshot.connections.map(\.id))
                for connection in preview.snapshot.connections where !localIDs.contains(connection.id) {
                    await extensions.browserSessions.clearSession(for: connection.id)
                }
                try await settings.restore(preview.snapshot, merge: merge, extensions: extensions.available, appVersion: AppBuild.displayVersion,
                    retainedConnectionIDs: Set(downloads.items.map { $0.record.identity.listing.connectionID }))
                try? await extensions.images.clear()
                dismiss()
            } catch { message = (error as? SettingsFailure)?.localizedDescription ?? "Restore could not finish. Your previous setup is still available." }
        }
    }
}

struct RecoveryBackupsView: View {
    let extensions: ExtensionEnvironment
    @State private var files: [URL] = []
    @State private var preview: BackupPreview?
    @State private var error: String?
    var body: some View {
        List {
            if files.isEmpty { ContentUnavailableView("No recovery copies", systemImage: "clock.arrow.circlepath", description: Text("A copy is saved here before each restore.")) }
            ForEach(files, id: \.self) { url in
                Button {
                    Task {
                        do {
                            let result = try await BackupFileReader.read(url)
                            preview = BackupPreview(archive: result.0, snapshot: result.1)
                        } catch { self.error = "This recovery copy could not be opened. Other copies are kept." }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery backup")
                        Text((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.formatted()) ?? "Saved before restore")
                            .font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                    }
                }
            }.listRowBackground(MidokuTheme.surface)
            if let error { Text(error).font(.footnote) }
        }.settingsStyle().navigationTitle("Recovery copies")
            .task {
                let root = URL.applicationSupportDirectory.appending(path: "Midoku/Recovery")
                files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]))?.filter { $0.pathExtension == "midoku" }.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                    ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                } ?? []
            }
            .sheet(item: $preview) { RestorePreviewView(preview: $0, extensions: extensions) }
    }
}
