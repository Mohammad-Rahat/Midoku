import Foundation
import SQLite3

/// SQLite supplies crash-safe transactions and relational identity constraints without a new runtime dependency.
/// The portable snapshot and relational index are committed together; neither is exported by copying a live DB.
nonisolated final class LibraryDatabase {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else { if let database { sqlite3_close(database) }; database = nil; throw SettingsFailure.storage }
        sqlite3_busy_timeout(database, 5000)
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA synchronous = FULL")
        let version = try scalar("PRAGMA user_version")
        guard version <= 1 else { throw SettingsFailure.futureVersion }
        if version == 0 {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE snapshot (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)")
                try execute("CREATE TABLE source (id TEXT PRIMARY KEY)")
                try execute("CREATE TABLE listing (id TEXT PRIMARY KEY, source TEXT NOT NULL REFERENCES source(id), external TEXT NOT NULL, UNIQUE(source, external))")
                try execute("CREATE TABLE chapter (id TEXT PRIMARY KEY, listing TEXT NOT NULL REFERENCES listing(id), external TEXT NOT NULL, UNIQUE(listing, external))")
                try execute("CREATE TABLE entry (id TEXT PRIMARY KEY)")
                try execute("CREATE TABLE slot (id TEXT PRIMARY KEY, entry TEXT NOT NULL REFERENCES entry(id), ordinal INTEGER NOT NULL, UNIQUE(entry, ordinal), UNIQUE(id, entry))")
                try execute("CREATE TABLE variant (id TEXT PRIMARY KEY, slot TEXT NOT NULL, entry TEXT NOT NULL, chapter TEXT NOT NULL REFERENCES chapter(id), FOREIGN KEY(slot, entry) REFERENCES slot(id, entry), UNIQUE(entry, chapter))")
                try execute("CREATE INDEX variant_source ON variant(chapter)")
                try execute("CREATE TABLE exclusion (entry TEXT NOT NULL REFERENCES entry(id), chapter TEXT NOT NULL REFERENCES chapter(id), PRIMARY KEY(entry, chapter))")
                try execute("PRAGMA user_version = 1")
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }
    deinit { if let database { sqlite3_close(database) } }

    func read() throws -> Data {
        let statement = try prepare("SELECT payload FROM snapshot WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SettingsFailure.storage }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, count <= BackupArchive.maximumBytes, let bytes = sqlite3_column_blob(statement, 0) else { throw SettingsFailure.storage }
        return Data(bytes: bytes, count: count)
    }

    func write(_ snapshot: AppSnapshot, payload: Data, rebuildIndex: Bool) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            if rebuildIndex {
                for table in ["variant", "exclusion", "slot", "entry", "chapter", "listing", "source"] { try execute("DELETE FROM \(table)") }
                for connection in snapshot.connections { try insert("INSERT INTO source VALUES (?)", [connection.id.uuidString]) }
                let library = snapshot.library
                for listing in library.listings { try insert("INSERT INTO listing VALUES (?, ?, ?)", [listing.id.uuidString, listing.identity.connectionID.uuidString, listing.identity.externalID]) }
                let listings = Dictionary(uniqueKeysWithValues: library.listings.map { ($0.identity, $0.id) })
                for chapter in library.chapters {
                    guard let listing = listings[chapter.identity.listing] else { throw LibraryFailure.invalid }
                    try insert("INSERT INTO chapter VALUES (?, ?, ?)", [chapter.id.uuidString, listing.uuidString, chapter.identity.externalID])
                }
                for entry in library.entries {
                    try insert("INSERT INTO entry VALUES (?)", [entry.id.uuidString])
                    for (order, slot) in entry.slots.enumerated() {
                        try insert("INSERT INTO slot VALUES (?, ?, ?)", [slot.id.uuidString, entry.id.uuidString, String(order)])
                        for variant in slot.variants { try insert("INSERT INTO variant VALUES (?, ?, ?, ?)", [variant.id.uuidString, slot.id.uuidString, entry.id.uuidString, variant.chapterID.uuidString]) }
                    }
                    for chapter in entry.exclusions { try insert("INSERT INTO exclusion VALUES (?, ?)", [entry.id.uuidString, chapter.uuidString]) }
                }
            }
            let statement = try prepare("INSERT INTO snapshot(id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload")
            defer { sqlite3_finalize(statement) }
            let bound = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw SettingsFailure.storage }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func insert(_ sql: String, _ values: [String]) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
            guard result == SQLITE_OK else { throw SettingsFailure.storage }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LibraryFailure.invalid }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw SettingsFailure.storage }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw SettingsFailure.storage }
        return statement
    }
    private func scalar(_ sql: String) throws -> Int {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SettingsFailure.storage }
        return Int(sqlite3_column_int(statement, 0))
    }
}
