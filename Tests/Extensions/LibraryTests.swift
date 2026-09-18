import Foundation
import Testing
import CryptoKit
@testable import MidokuExtensions

@Suite("Personal library and mixed-source chapters")
struct LibraryTests {
    private func fixture() -> AppSnapshot {
        var state = AppSnapshot()
        state.connections = [SourceConnection(extensionID: "dev.midoku.fixture-a", name: "Source A"), SourceConnection(extensionID: "dev.midoku.fixture-b", name: "Source B")]
        return state
    }
    private func details(_ source: String = "a", title: String = "Example series") -> MangaDetails {
        MangaDetails(id: source, title: title, description: "Source description", coverURL: nil)
    }
    private func records(_ numbers: [Int], prefix: String = "a") -> [ChapterRecord] {
        numbers.map { ChapterRecord(id: "\(prefix)-\($0)", title: "Chapter \($0)", number: String($0), ordinal: $0, language: "en") }
    }
    private func entry(_ state: AppSnapshot, _ id: UUID) throws -> PersonalEntry { try #require(state.library.entry(id)) }
    private func numbers(_ state: AppSnapshot, _ id: UUID) throws -> [String] { try entry(state, id).slots.compactMap(\.preferred).compactMap { state.library.number($0) } }

    @Test func fillsSourceAGapWithBWithoutImportingTheWholeSeriesAndSurvivesRestart() async throws {
        var state = fixture()
        let a = state.connections[0].id, b = state.connections[1].id
        let id = try state.library.add(details: details(), connectionID: a, records: records(Array(1...20) + Array(22...50)), language: "en")
        _ = try state.library.remember(details: details("b"), connectionID: b, records: records(Array(1...50), prefix: "b"), complete: true)
        let missing = try #require(state.library.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "21" })
        try state.library.copy([CopiedChapter(chapterID: missing.id)])
        let preview = try state.library.pastePreview(entryID: id)
        #expect(preview.first?.action == .separate)
        try state.library.paste(entryID: id, revision: try entry(state, id).sequenceRevision, choices: preview)
        #expect(try numbers(state, id) == (1...50).map(String.init))
        let result = try entry(state, id)
        #expect(result.links.count == 2)
        #expect(result.links.last?.followsNewChapters == false)
        let sequence = result.slots[19...21].compactMap(\.preferred).compactMap { state.library.chapter($0.chapterID)?.identity.listing.connectionID }
        #expect(sequence == [a, b, a])
        try state.validate()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = SettingsPersistence(fileURL: root.appending(path: "library.sqlite"))
        try await persistence.save(state, revision: 1)
        let reloaded = try #require(try await SettingsPersistence(fileURL: root.appending(path: "library.sqlite")).load())
        #expect(try numbers(reloaded, id) == (1...50).map(String.init))
        #expect(reloaded.library.clipboard.first?.chapterID == missing.id)
        var refreshed = reloaded
        try refreshed.library.refresh(details: details("b"), connectionID: b, records: records(Array(1...51), prefix: "b"), language: "en")
        #expect(try entry(refreshed, id).slots.count == 50)
    }

    @Test func equalNumbersRequireChoiceAndAlternativesKeepPhysicalProgress() throws {
        var state = fixture()
        let id = try state.library.add(details: details(), connectionID: state.connections[0].id, records: records([1]), language: "en")
        let original = try #require(state.library.chapters.first)
        state.library.completed.insert(original.identity)
        state.progress = [ReadingPosition(identity: original.identity, pageID: "a-page", pageIndex: 8, pageCount: 10, fraction: 0.5, updatedAt: .now)]
        _ = try state.library.remember(details: details("b"), connectionID: state.connections[1].id, records: records([1], prefix: "b"), complete: true)
        let incoming = try #require(state.library.chapters.last)
        try state.library.copy([CopiedChapter(chapterID: incoming.id)])
        var preview = try state.library.pastePreview(entryID: id)
        #expect(preview[0].action == .unresolved)
        #expect(throws: (any Error).self) { try state.library.paste(entryID: id, revision: 0, choices: preview) }
        preview[0].action = .alternative
        try state.library.paste(entryID: id, revision: 0, choices: preview)
        var slot = try #require(try entry(state, id).slots.first)
        #expect(slot.variants.count == 2)
        #expect(state.library.isRead(slot))
        let preferred = slot.variants[1].id
        try state.library.editEntry(id) { $0.slots[0].preferredID = preferred }
        slot = try #require(try entry(state, id).slots.first)
        #expect(!state.library.isRead(slot))
        #expect(!state.progress.contains { $0.id == incoming.identity })
        #expect(state.progress.first?.pageIndex == 8)
    }

    @Test func replacementAndExclusionsDoNotTransferPagePositionOrReappear() throws {
        var state = fixture()
        let id = try state.library.add(details: details(), connectionID: state.connections[0].id, records: records([1, 2]), language: "en")
        let original = try #require(state.library.chapters.first)
        state.library.completed.insert(original.identity)
        _ = try state.library.remember(details: details("b"), connectionID: state.connections[1].id, records: records([1], prefix: "b"), complete: true)
        let replacement = try #require(state.library.chapters.last)
        try state.library.copy([CopiedChapter(chapterID: replacement.id)])
        var choices = try state.library.pastePreview(entryID: id)
        choices[0].action = .replace; choices[0].preserveCompletion = true
        try state.library.paste(entryID: id, revision: 0, choices: choices)
        #expect(try entry(state, id).exclusions.contains(original.id))
        #expect(try entry(state, id).slots[0].completionOverride == true)
        #expect(!state.library.completed.contains(replacement.identity))
        try state.library.refresh(details: details(title: "Updated source title"), connectionID: state.connections[0].id, records: records([1, 2, 3]), language: "en")
        #expect(try entry(state, id).slots.count == 3)
        #expect(!(try entry(state, id).slots.flatMap(\.variants).contains { $0.chapterID == original.id }))
        let removed = try entry(state, id).slots[1]
        try state.library.removeSlots(entryID: id, slotIDs: [removed.id])
        try state.library.refresh(details: details(), connectionID: state.connections[0].id, records: records([1, 2, 3]), language: "en")
        #expect(try entry(state, id).slots.count == 2)
        try state.library.restoreChapter(entryID: id, chapterID: try #require(removed.preferred?.chapterID))
        #expect(try entry(state, id).slots.count == 3)
        try state.validate()
    }

    @Test func refreshPreservesOverridesManualOrderAndMissingReferences() throws {
        var state = fixture()
        let id = try state.library.add(details: details(), connectionID: state.connections[0].id, records: records([1, 2, 3]), language: "en")
        try state.library.editEntry(id) { $0.titleOverride = "My title"; $0.descriptionOverride = ""; $0.slots[0].variants[0].edits.title = "My chapter" }
        let third = try entry(state, id).slots[2].id
        try state.library.moveSlot(entryID: id, slotID: third, offset: -1)
        try state.library.refresh(details: details(title: "Remote update"), connectionID: state.connections[0].id, records: records([1, 3, 4]), language: "en")
        #expect(try numbers(state, id) == ["1", "3", "2", "4"])
        #expect(state.library.title(try entry(state, id)) == "My title")
        #expect(state.library.description(try entry(state, id)).isEmpty)
        #expect(state.library.chapters.first { $0.record.number == "2" }?.available == false)
        #expect(state.library.updates.count == 1)
        try state.library.refresh(details: details(), connectionID: state.connections[0].id, records: records([1, 3, 4]), language: "en")
        #expect(state.library.updates.count == 1)
    }

    @Test func stalePasteAndUnconfirmedRestorationAreAtomic() throws {
        var state = fixture()
        let id = try state.library.add(details: details(), connectionID: state.connections[0].id, records: records([1, 2]), language: "en")
        let removed = try entry(state, id).slots[1]
        try state.library.removeSlots(entryID: id, slotIDs: [removed.id])
        try state.library.copy([CopiedChapter(chapterID: try #require(removed.preferred?.chapterID))])
        var preview = try state.library.pastePreview(entryID: id)
        let revision = try entry(state, id).sequenceRevision
        #expect(throws: (any Error).self) { try state.library.paste(entryID: id, revision: revision, choices: preview) }
        #expect(try entry(state, id).slots.count == 1)
        preview[0].restoreExcluded = true
        try state.library.editEntry(id) { $0.status = .reading }
        #expect(throws: (any Error).self) { try state.library.paste(entryID: id, revision: revision, choices: preview) }
        #expect(try entry(state, id).slots.count == 1)
    }

    @Test func followBaselineOnlyAddsNewReleases() throws {
        var state = fixture()
        let id = try state.library.add(details: details(), connectionID: state.connections[0].id, records: records([1]), language: "en")
        _ = try state.library.remember(details: details(), connectionID: state.connections[0].id, records: records([1, 2]), complete: true)
        let baseline = Set(state.library.chapters.map(\.id))
        try state.library.editEntry(id) { $0.links[0].followBaseline = baseline }
        try state.library.refresh(details: details(), connectionID: state.connections[0].id, records: records([1, 2, 3]), language: "en")
        #expect(try numbers(state, id) == ["1", "3"])
    }

    @Test func decimalNumbersDoNotConflateSpecialChapterNames() throws {
        #expect(LibraryState.sameNumber("21.0", "21"))
        #expect(!LibraryState.sameNumber("21 extra", "21"))
        #expect(!LibraryState.sameNumber("21a", "21b"))
        var state = fixture()
        let chapters = ["10", "2.5", "2", "Special", "1"].enumerated().map { ChapterRecord(id: "\($0.offset)", title: $0.element, number: $0.element, ordinal: $0.offset, language: "en") }
        let id = try state.library.add(details: details(), connectionID: state.connections[0].id, records: chapters, language: "en")
        #expect(try numbers(state, id) == ["1", "2", "2.5", "10", "Special"])
    }

    @Test func libraryBackupMergeRemapsSharedIdentitiesAndCategoryNames() throws {
        var local = fixture()
        local.categories = [LibraryCategory(name: "Reading")]
        let localID = try local.library.add(details: details(), connectionID: local.connections[0].id, records: records([1]), language: "en", categories: [local.categories[0].id])
        var incoming = fixture(); incoming.connections = local.connections
        incoming.categories = [LibraryCategory(name: "reading")]
        let importedID = try incoming.library.add(details: details(), connectionID: incoming.connections[0].id, records: records([1, 2]), language: "en", categories: [incoming.categories[0].id])
        let (_, decoded) = try BackupArchive.decode(try BackupArchive(snapshot: incoming, extensions: [], appVersion: "test").encoded())
        let result = try local.merging(decoded)
        try result.validate()
        #expect(result.library.entries.count == 2)
        #expect(result.library.listings.count == 1)
        #expect(result.library.chapters.count == 2)
        #expect(try entry(result, importedID).categoryIDs == [local.categories[0].id])
        #expect(try entry(result, localID).slots[0].preferred?.chapterID == entry(result, importedID).slots[0].preferred?.chapterID)
    }

    @Test func databaseConstraintFailureRollsBackBothPayloadAndIndex() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var valid = fixture()
        let id = try valid.library.add(details: details(), connectionID: valid.connections[0].id, records: records([1]), language: "en")
        let database = try LibraryDatabase(url: root.appending(path: "library.sqlite"))
        let original = try JSONEncoder().encode(valid)
        try database.write(valid, payload: original, rebuildIndex: true)
        var invalid = valid
        let variant = try #require(try entry(valid, id).slots[0].preferred)
        invalid.library.entries[0].slots.append(ChapterSlot(variant: ChapterVariant(chapterID: variant.chapterID)))
        #expect(throws: (any Error).self) { try database.write(invalid, payload: Data("invalid".utf8), rebuildIndex: true) }
        #expect(try database.read() == original)
    }

    @Test func legacySettingsJSONMigratesWithoutDeletingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var legacy = fixture(); legacy.categories = [LibraryCategory(name: "Original")]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json["version"] = 1; json.removeValue(forKey: "library")
        let bytes = try JSONSerialization.data(withJSONObject: json)
        let oldURL = root.appending(path: "app-settings.json")
        try bytes.write(to: oldURL)
        let migrated = try #require(try await SettingsPersistence(fileURL: root.appending(path: "library.sqlite"), legacyJSON: oldURL).load())
        #expect(migrated.version == 2)
        #expect(migrated.categories == legacy.categories)
        #expect(migrated.connections == legacy.connections)
        #expect(migrated.library.entries.isEmpty)
        #expect(try Data(contentsOf: oldURL) == bytes)
    }

    @Test func oldBackupEnvelopeIsStillAccepted() throws {
        let state = fixture()
        var payloadJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        payloadJSON["version"] = 1; payloadJSON.removeValue(forKey: "library")
        let payload = try JSONSerialization.data(withJSONObject: payloadJSON)
        let archive = try BackupArchive(snapshot: state, extensions: [], appVersion: "old")
        var json = try #require(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
        json["version"] = 1; json["payload"] = payload.base64EncodedString(); json["byteCount"] = payload.count
        json["sha256"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        var counts = try #require(json["counts"] as? [String: Any]); for key in ["libraryEntries", "chapters", "covers"] { counts.removeValue(forKey: key) }; json["counts"] = counts
        let (_, restored) = try BackupArchive.decode(JSONSerialization.data(withJSONObject: json))
        #expect(restored.connections == state.connections)
        #expect(restored.library.entries.isEmpty)
    }
}
