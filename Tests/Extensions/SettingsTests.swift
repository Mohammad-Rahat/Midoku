import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Settings data retention")
struct SettingsTests {
    private func state() -> AppSnapshot {
        var state = AppSnapshot()
        state.connections = [SourceConnection(extensionID: "dev.midoku.example", name: "Example")]
        return state
    }
    private func record(_ number: Int, in state: AppSnapshot) throws -> ReadingRecord {
        let connection = try #require(state.connections.first)
        return ReadingRecord(identity: SourceChapterIdentity(listing: SourceListingIdentity(connectionID: connection.id, externalID: "manga"), externalID: "chapter-\(number)"),
            mangaTitle: "Example manga", sourceName: "Example", chapter: ChapterRecord(id: "chapter-\(number)", title: "Chapter", number: "\(number)", ordinal: number, language: "en"),
            openedAt: Date(timeIntervalSince1970: Double(number)))
    }
    @Test func historyPruningAndClearingPreservePhysicalProgress() throws {
        var state = state()
        let first = try record(0, in: state)
        let progress = ReadingPosition(identity: first.id, pageID: "page-a", pageIndex: 2, pageCount: 10, fraction: 0.4, updatedAt: Date())
        state.progress = [progress]
        for number in 0...100 { state.opened(try record(number, in: state)) }
        #expect(state.history.count == 100)
        #expect(!state.history.contains { $0.id == first.id })
        #expect(state.progress.first?.pageIndex == 2)
        state.history.removeAll()
        #expect(state.progress.first?.fraction == 0.4)
        state.preferences.recordHistory = false
        state.opened(first)
        #expect(state.history.isEmpty)
    }
    @Test func backupRoundTripsAndRejectsTampering() throws {
        var state = state()
        state.preferences.appLock = true
        state.preferences.reader.mode = .continuous
        state.categories = [LibraryCategory(name: "Weekend")]
        state.history = [try record(1, in: state)]
        let archive = try BackupArchive(snapshot: state, extensions: [], appVersion: "1.0")
        let data = try archive.encoded()
        let (_, restored) = try BackupArchive.decode(data)
        #expect(restored.connections.first?.id == state.connections.first?.id)
        #expect(restored.preferences.reader.mode == .continuous)
        #expect(!restored.preferences.appLock)
        #expect(restored.categories == state.categories)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["sha256"] = "incorrect"
        let invalid = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: SettingsFailure.invalidBackup) { try BackupArchive.decode(invalid) }
        json["version"] = 999
        let future = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: SettingsFailure.futureVersion) { try BackupArchive.decode(future) }
    }
    @Test func mergePreservesLocalEditsAndRejectsSourceIdentityReuse() throws {
        var local = state()
        let localRecord = try record(1, in: local)
        local.progress = [ReadingPosition(identity: localRecord.id, pageID: "local", pageIndex: 1, pageCount: 10, fraction: 0, updatedAt: .distantPast)]
        local.categories = [LibraryCategory(name: "Reading")]
        var imported = local
        imported.preferences.appearance = .dark
        imported.progress[0].pageIndex = 9
        imported.progress[0].updatedAt = .distantFuture
        imported.categories[0].name = "Remote edit"
        imported.categories.append(LibraryCategory(name: "Weekend"))
        let result = try local.merging(imported)
        #expect(result.preferences.appearance == .system)
        #expect(result.progress[0].pageIndex == 1)
        #expect(result.categories[0].name == "Reading")
        #expect(result.categories.count == 2)
        let identity = try #require(local.connections.first?.id)
        imported.connections = [SourceConnection(id: identity, extensionID: "different.extension", name: "Collision")]
        #expect(throws: SettingsFailure.identityConflict) { try local.merging(imported) }
    }
    @Test func duplicateCategoriesAndDanglingPinsAreRejected() throws {
        var state = state()
        state.categories = [LibraryCategory(name: " Reading "), LibraryCategory(name: "reading")]
        #expect(throws: SettingsFailure.duplicateIdentity) { try state.validate() }
        state.categories = []
        state.homeSections = [HomeSection(connectionID: UUID(), feedID: "popular", query: "", filters: [:], sourceTitle: "Example", title: "Popular")]
        #expect(throws: SettingsFailure.invalidBackup) { try state.validate() }
    }
    @Test func pinIdentityIgnoresDictionaryAndMultiselectOrder() throws {
        let connection = UUID()
        let first = HomeSection(connectionID: connection, feedID: "popular", query: "", filters: ["tags": ["b", "a"], "language": ["en"]], sourceTitle: "Source", title: "Popular")
        var second = first
        second.id = UUID(); second.title = "Custom name"
        second.filters = ["language": ["en"], "tags": ["a", "b"]]
        #expect(first.hasSameQuery(as: second))
        second.filters["language"] = ["ja"]
        #expect(!first.hasSameQuery(as: second))
    }
    @Test func staleWritesAndInvalidRestoreCannotReplaceSavedState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "settings.json")
        let persistence = SettingsPersistence(fileURL: url)
        var old = state(); old.categories = [LibraryCategory(name: "Old")]
        var current = old; current.categories[0].name = "New"
        try await persistence.save(current, revision: 2)
        try await persistence.save(old, revision: 1)
        var invalid = old; invalid.version = 99
        await #expect(throws: SettingsFailure.futureVersion) { try await persistence.save(invalid, revision: 3) }
        let restored = try await persistence.load()
        #expect(restored?.categories.first?.name == "New")
        try Data("corrupted".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await persistence.load() }
        #expect(try String(contentsOf: url, encoding: .utf8) == "corrupted")
    }
    @Test func lockCancellationAndDelayStayClosed() {
        var lock = LockState()
        lock.configure(enabled: true)
        #expect(lock.isLocked)
        // An unsuccessful/cancelled auth never calls authenticated().
        lock.activate(at: .now, enabled: true, delay: .immediately)
        #expect(lock.isLocked)
        lock.authenticated()
        let start = Date(timeIntervalSince1970: 1000)
        lock.background(at: start, enabled: true, delay: .oneMinute)
        lock.activate(at: start.addingTimeInterval(59), enabled: true, delay: .oneMinute)
        #expect(!lock.isLocked)
        lock.background(at: start, enabled: true, delay: .oneMinute)
        lock.activate(at: start.addingTimeInterval(60), enabled: true, delay: .oneMinute)
        #expect(lock.isLocked)
        lock.authenticated()
        lock.background(at: start, enabled: true, delay: .immediately)
        #expect(lock.isLocked)
    }
    @Test func legacyConnectionsDecodeWithoutLosingUUID() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"extensionID\":\"dev.midoku.example\",\"name\":\"Example\",\"isEnabled\":true}".utf8)
        let connection = try JSONDecoder().decode(SourceConnection.self, from: data)
        #expect(connection.id == id)
        #expect(!connection.isArchived)
    }
    @Test func downloadsRequireCompleteValidatedFilesAndRecoverPromotion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DownloadStorage(root: root)
        let id = UUID()
        try await storage.begin(id)
        let page = try await storage.write(Data("page bytes".utf8), id: id, pageID: "one", index: 0)
        let record = try record(1, in: state())
        var job = SavedDownload(id: id, record: record, status: .downloading, pages: [page], expectedPages: 2)
        await #expect(throws: SettingsFailure.invalidBackup) { try await storage.complete(job) }
        job.expectedPages = 1
        try await storage.save([job], revision: 1)
        try await storage.complete(job)
        let recovered = try await storage.load()
        #expect(recovered.first?.status == .completed)
        #expect(try await storage.page(page, in: id) == Data("page bytes".utf8))
        let pageURL = root.appending(path: "chapter-\(id.uuidString)/0.page")
        try Data("corrupted!".utf8).write(to: pageURL)
        await #expect(throws: SettingsFailure.invalidBackup) { try await storage.page(page, in: id) }
    }
}

@Suite("Settings migration and restore")
@MainActor
struct SettingsRestoreTests {
    @Test func migratesConnectionsAndKeepsRecoveryBeforeAtomicReplace() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = SourceConnectionStore(fileURL: root.appending(path: "source-connections.json"))
        let connection = SourceConnection(extensionID: "dev.midoku.example", name: "Saved source")
        try await legacy.save([connection])
        let store = AppSettingsStore(root: root)
        await store.load()
        #expect(store.isReady)
        #expect(store.snapshot.connections.first?.id == connection.id)
        store.update { $0.categories = [LibraryCategory(name: "Original")]; $0.preferences.lockDelay = .fiveMinutes }
        try await store.flush()
        try await store.setAppLock(true)
        var imported = AppSnapshot()
        imported.categories = [LibraryCategory(name: "Imported")]
        imported.preferences.appLock = false
        imported.preferences.protectAppSwitcher = false
        let recovery = root.appending(path: "Recovery")
        try Data("blocked directory".utf8).write(to: recovery)
        await #expect(throws: (any Error).self) {
            try await store.restore(imported, merge: false, extensions: [], appVersion: "test")
        }
        #expect(store.snapshot.categories.first?.name == "Original")
        #expect(!store.isRestoring)
        try FileManager.default.removeItem(at: recovery)
        try await store.restore(imported, merge: false, extensions: [], appVersion: "test", retainedConnectionIDs: [connection.id])
        #expect(store.snapshot.categories.first?.name == "Imported")
        #expect(store.snapshot.preferences.appLock)
        #expect(store.snapshot.preferences.lockDelay == .fiveMinutes)
        #expect(store.snapshot.preferences.protectAppSwitcher)
        #expect(store.snapshot.connections.first?.id == connection.id)
        #expect(store.snapshot.connections.first?.isArchived == true)
        let files = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        let file = try #require(files.first)
        let (_, original) = try BackupArchive.decode(Data(contentsOf: file))
        #expect(original.categories.first?.name == "Original")
        let reloaded = AppSettingsStore(root: root)
        await reloaded.load()
        #expect(reloaded.snapshot.categories.first?.name == "Imported")
        #expect(reloaded.snapshot.preferences.appLock)
    }
}
