import Foundation
import CryptoKit

/// A transactional database snapshot keeps library/settings restore all-or-nothing.
actor SettingsPersistence {
    let fileURL: URL
    let legacyJSON: URL?
    private var savedRevision = -1
    private var indexedState: Data?
    init(fileURL: URL, legacyJSON: URL? = nil) { self.fileURL = fileURL; self.legacyJSON = legacyJSON }

    func load() throws -> AppSnapshot? {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard let legacyJSON, FileManager.default.fileExists(atPath: legacyJSON.path) else { return nil }
            let data = try Data(contentsOf: legacyJSON)
            guard data.count <= BackupArchive.maximumBytes else { throw SettingsFailure.tooLarge }
            let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: data)
            try snapshot.validate()
            try save(snapshot, revision: 0)
            return snapshot
        }
        let database = try LibraryDatabase(url: fileURL)
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: database.read())
        try snapshot.validate()
        return snapshot
    }

    func save(_ snapshot: AppSnapshot, revision: Int) throws {
        guard revision >= savedRevision else { return }
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= BackupArchive.maximumBytes else { throw SettingsFailure.tooLarge }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = FileManager.default.fileExists(atPath: fileURL.path)
        do {
            let database = try LibraryDatabase(url: fileURL)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: fileURL.path)
            #endif
            // Reading-position writes do not rebuild the identity index.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let index = try encoder.encode(snapshot.library) + encoder.encode(snapshot.connections)
            try database.write(snapshot, payload: data, rebuildIndex: indexedState != index)
            indexedState = index
            savedRevision = revision
        } catch {
            // Only remove our newly created, uncommitted database; never remove a user's existing store.
            if !existed { try? FileManager.default.removeItem(at: fileURL) }
            throw error
        }
    }
}

nonisolated struct BackupCounts: Codable, Equatable, Sendable {
    let sources: Int
    let categories: Int
    let homeSections: Int
    let history: Int
    let progress: Int
    var libraryEntries: Int? = nil
    var chapters: Int? = nil
    var covers: Int? = nil
    init(_ snapshot: AppSnapshot) {
        sources = snapshot.connections.count
        categories = snapshot.categories.count
        homeSections = snapshot.homeSections.count
        history = snapshot.history.count
        progress = snapshot.progress.count
        libraryEntries = snapshot.library.entries.count
        chapters = snapshot.library.chapters.count
        covers = snapshot.library.covers.count
    }
}

/// JSON envelope is intentionally data-only: it cannot carry executable bundles, cookies or filesystem paths.
nonisolated struct BackupArchive: Codable, Sendable {
    static let maximumBytes = 32 * 1024 * 1024
    let format: String
    let version: Int
    let exportedAt: Date
    let appVersion: String
    let extensions: [ExtensionInventory]
    let counts: BackupCounts
    let byteCount: Int
    let sha256: String
    let payload: Data

    struct ExtensionInventory: Codable, Sendable {
        let id: String
        let version: String
    }
    init(snapshot: AppSnapshot, extensions: [ExtensionManifest], appVersion: String) throws {
        try snapshot.validate()
        var export = snapshot
        // Lock enrollment belongs to the current device; never enable a lock via an imported file.
        export.preferences.appLock = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        payload = try encoder.encode(export)
        byteCount = payload.count
        sha256 = Self.digest(payload)
        format = "dev.midoku.settings-backup"
        version = 2
        exportedAt = Date()
        self.appVersion = appVersion
        self.extensions = extensions.map { ExtensionInventory(id: $0.id, version: $0.version) }
        counts = BackupCounts(export)
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw SettingsFailure.tooLarge }
        return data
    }
    static func decode(_ data: Data) throws -> (BackupArchive, AppSnapshot) {
        guard data.count <= maximumBytes else { throw SettingsFailure.tooLarge }
        do {
            let archive = try JSONDecoder().decode(Self.self, from: data)
            guard archive.format == "dev.midoku.settings-backup" else { throw SettingsFailure.invalidBackup }
            guard (1...2).contains(archive.version) else { throw SettingsFailure.futureVersion }
            guard archive.byteCount == archive.payload.count, archive.sha256 == digest(archive.payload),
                  archive.exportedAt.timeIntervalSince1970.isFinite, archive.extensions.count <= 1000 else { throw SettingsFailure.invalidBackup }
            let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: archive.payload)
            try snapshot.validate()
            var expected = BackupCounts(snapshot)
            if archive.version == 1 { expected.libraryEntries = nil; expected.chapters = nil; expected.covers = nil }
            guard archive.counts == expected else { throw SettingsFailure.invalidBackup }
            return (archive, snapshot)
        } catch let error as SettingsFailure { throw error }
        catch { throw SettingsFailure.invalidBackup }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

nonisolated struct LockState: Sendable {
    private(set) var isLocked = true
    private var backgroundedAt: Date?
    mutating func configure(enabled: Bool) { isLocked = enabled }
    mutating func authenticated() { isLocked = false; backgroundedAt = nil }
    mutating func background(at date: Date, enabled: Bool, delay: LockDelay) {
        backgroundedAt = date
        if enabled && delay == .immediately { isLocked = true }
    }
    mutating func activate(at date: Date, enabled: Bool, delay: LockDelay) {
        if enabled, let backgroundedAt, date.timeIntervalSince(backgroundedAt) >= delay.seconds { isLocked = true }
        if !enabled { isLocked = false }
        backgroundedAt = nil
    }
}
