import Foundation
import CryptoKit

/// A single atomic snapshot makes settings/source restore all-or-nothing. Never deletes an unreadable store.
actor SettingsPersistence {
    let fileURL: URL
    private var savedRevision = -1
    init(fileURL: URL) { self.fileURL = fileURL }

    func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= BackupArchive.maximumBytes else { throw SettingsFailure.tooLarge }
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }

    func save(_ snapshot: AppSnapshot, revision: Int) throws {
        guard revision >= savedRevision else { return }
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= BackupArchive.maximumBytes else { throw SettingsFailure.tooLarge }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        savedRevision = revision
    }
}

nonisolated struct BackupCounts: Codable, Equatable, Sendable {
    let sources: Int
    let categories: Int
    let homeSections: Int
    let history: Int
    let progress: Int
    init(_ snapshot: AppSnapshot) {
        sources = snapshot.connections.count
        categories = snapshot.categories.count
        homeSections = snapshot.homeSections.count
        history = snapshot.history.count
        progress = snapshot.progress.count
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
        version = 1
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
            guard archive.version == 1 else { throw SettingsFailure.futureVersion }
            guard archive.byteCount == archive.payload.count, archive.sha256 == digest(archive.payload),
                  archive.exportedAt.timeIntervalSince1970.isFinite, archive.extensions.count <= 1000 else { throw SettingsFailure.invalidBackup }
            let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: archive.payload)
            try snapshot.validate()
            guard archive.counts == BackupCounts(snapshot) else { throw SettingsFailure.invalidBackup }
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
