import Foundation
import Observation

@MainActor
@Observable
final class AppSettingsStore {
    private(set) var snapshot = AppSnapshot()
    private(set) var isReady = false
    private(set) var isRestoring = false
    private(set) var saveError: String?
    private(set) var loadError: String?
    private(set) var revision = 0
    private(set) var restoreGeneration = UUID()
    private let persistence: SettingsPersistence
    private let root: URL

    init(root: URL = URL.applicationSupportDirectory.appending(path: "Midoku", directoryHint: .isDirectory)) {
        self.root = root
        persistence = SettingsPersistence(fileURL: root.appending(path: "library.sqlite"), legacyJSON: root.appending(path: "app-settings.json"))
    }

    func load() async {
        guard !isReady else { return }
        do {
            if let saved = try await persistence.load() { snapshot = saved }
            else {
                let legacy = SourceConnectionStore(fileURL: root.appending(path: "source-connections.json"))
                var migrated = AppSnapshot()
                migrated.connections = try await legacy.load()
                try await persistence.save(migrated, revision: revision)
                snapshot = migrated
            }
            loadError = nil
            isReady = true
        } catch {
            loadError = (error as? SettingsFailure)?.localizedDescription ?? "Midoku could not open its saved settings. The original files have been preserved."
        }
    }

    func update(_ edit: (inout AppSnapshot) throws -> Void) {
        guard isReady, !isRestoring else { return }
        do {
            var updated = snapshot
            try edit(&updated)
            try updated.validate()
            revision += 1
            let currentRevision = revision
            snapshot = updated
            Task {
                do {
                    try await persistence.save(updated, revision: currentRevision)
                    if revision == currentRevision { saveError = nil }
                } catch {
                    if revision == currentRevision { saveError = SettingsFailure.storage.localizedDescription }
                }
            }
        } catch { saveError = error.localizedDescription }
    }

    func flush() async throws {
        guard isReady, !isRestoring else { throw SettingsFailure.storage }
        do {
            try await persistence.save(snapshot, revision: revision)
            saveError = nil
        } catch {
            saveError = SettingsFailure.storage.localizedDescription
            throw error
        }
    }
    func setAppLock(_ enabled: Bool) async throws {
        guard isReady, !isRestoring else { throw SettingsFailure.storage }
        var candidate = snapshot
        candidate.preferences.appLock = enabled
        isRestoring = true
        defer { isRestoring = false }
        revision += 1
        try await persistence.save(candidate, revision: revision)
        snapshot = candidate
        saveError = nil
    }

    /// User-facing curation is published only after the complete transaction is durable.
    func commit(_ edit: (inout AppSnapshot) throws -> Void) async throws {
        guard isReady, !isRestoring else { throw SettingsFailure.storage }
        var candidate = snapshot
        try edit(&candidate)
        try candidate.validate()
        isRestoring = true
        defer { isRestoring = false }
        revision += 1
        try await persistence.save(candidate, revision: revision)
        snapshot = candidate
        saveError = nil
    }

    func deleteCategory(_ id: UUID) {
        update { state in
            state.categories.removeAll { $0.id == id }
            for index in state.library.entries.indices { state.library.entries[index].categoryIDs.remove(id) }
        }
    }

    func dismissSaveError() { saveError = nil }

    func saveCategory(id: UUID?, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { throw SettingsFailure.emptyName }
        guard !snapshot.categories.contains(where: {
            $0.id != id && LibraryCategory.normalized($0.name) == LibraryCategory.normalized(trimmed)
        }) else { throw SettingsFailure.duplicateName }
        update { state in
            if let id, let index = state.categories.firstIndex(where: { $0.id == id }) { state.categories[index].name = trimmed }
            else { state.categories.append(LibraryCategory(name: trimmed)) }
        }
    }

    @discardableResult
    func pin(_ section: HomeSection) -> Bool {
        guard !snapshot.homeSections.contains(where: { $0.hasSameQuery(as: section) }) else { return false }
        update { $0.homeSections.append(section) }
        return true
    }

    func savePosition(_ position: ReadingPosition) {
        update { state in
            if let index = state.progress.firstIndex(where: { $0.id == position.id }) {
                if state.progress[index].updatedAt <= position.updatedAt { state.progress[index] = position }
            } else { state.progress.append(position) }
        }
    }

    func restore(_ imported: AppSnapshot, merge: Bool, extensions: [ExtensionManifest], appVersion: String, retainedConnectionIDs: Set<UUID> = []) async throws {
        guard isReady, !isRestoring else { throw SettingsFailure.storage }
        try imported.validate()
        // Reject UUID reuse even for Replace, before changing any files.
        for incoming in imported.connections {
            if let local = snapshot.connections.first(where: { $0.id == incoming.id }), local.extensionID != incoming.extensionID {
                throw SettingsFailure.identityConflict
            }
        }
        var candidate = merge ? try snapshot.merging(imported) : imported
        // Preserve source identity for independent offline files retained across a Replace restore.
        for connection in snapshot.connections where retainedConnectionIDs.contains(connection.id) && !candidate.connections.contains(where: { $0.id == connection.id }) {
            var retained = connection
            retained.isEnabled = false; retained.isArchived = true
            candidate.connections.append(retained)
        }
        candidate.preferences.appLock = snapshot.preferences.appLock
        candidate.preferences.lockDelay = snapshot.preferences.lockDelay
        candidate.preferences.protectAppSwitcher = snapshot.preferences.protectAppSwitcher
        try candidate.validate()
        isRestoring = true
        defer { isRestoring = false }
        let local = snapshot
        let recoveryURL = root.appending(path: "Recovery", directoryHint: .isDirectory)
            .appending(path: "before-restore-\(UUID().uuidString).midoku")
        // Recovery is mandatory for both modes; restore aborts if it cannot be written.
        try await Task.detached {
            let archive = try BackupArchive(snapshot: local, extensions: extensions, appVersion: appVersion)
            try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try archive.encoded().write(to: recoveryURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try archive.encoded().write(to: recoveryURL, options: .atomic)
            #endif
        }.value
        revision += 1
        try await persistence.save(candidate, revision: revision)
        snapshot = candidate
        restoreGeneration = UUID()
        saveError = nil
    }
}
