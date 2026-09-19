import Foundation
import Testing
@testable import MidokuCollectionCore

@Suite("Midoku mixed-source composition")
struct CollectionTests {
    let a = UUID(), b = UUID()
    func details(_ id: String = "same-key") -> MCMangaDetails { .init(id: id, title: "Original", description: "Source text", coverURL: nil) }
    func records(_ numbers: [Int]) -> [MCChapterRecord] {
        numbers.map { .init(id: "chapter-\($0)", title: "Episode \($0)", number: String($0), ordinal: $0, language: "en") }
    }
    func mixed() throws -> (MCLibraryState, UUID) {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([20, 22]), language: nil)
        _ = try state.remember(details: details(), connectionID: b, records: records([20, 21, 22]), complete: true)
        let chapter = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "21" })
        try state.copy([MCCopiedChapter(chapterID: chapter.id)])
        try state.paste(entryID: id, revision: 0, choices: state.pastePreview(entryID: id))
        return (state, id)
    }
    @Test func sourceAToBToASurvivesRestartAndRefresh() throws {
        let (original, id) = try mixed()
        var state = try JSONDecoder().decode(MCLibraryState.self, from: JSONEncoder().encode(original))
        try state.refresh(details: details(), connectionID: b, records: records([20, 21, 22, 23]), language: nil)
        let entry = try #require(state.entry(id))
        #expect(entry.slots.compactMap(\.preferred).compactMap { state.chapter($0.chapterID)?.identity.listing.connectionID } == [a, b, a])
        #expect(entry.links.last?.followsNewChapters == false)
        #expect(state.clipboard.isEmpty)
        try state.validate(connections: [a, b], categories: [])
    }
    @Test func pasteIsIdempotentAndSourceIDsDoNotCollide() throws {
        var (state, id) = try mixed()
        let pasted = try #require(state.entry(id)?.slots.first?.preferred)
        try state.copy([MCCopiedChapter(chapterID: pasted.chapterID)])
        let revision = try #require(state.entry(id)).sequenceRevision
        try state.paste(entryID: id, revision: revision, choices: state.pastePreview(entryID: id))
        #expect(state.entry(id)?.slots.count == 3)
        #expect(state.chapters.filter { $0.record.id == "chapter-20" }.count == 2)
    }
    @Test func editingSurvivesRefreshAndResetKeepsComposition() throws {
        var (state, id) = try mixed()
        try state.editEntry(id) { $0.titleOverride = "My edition"; $0.descriptionOverride = ""; $0.slots[0].variants[0].edits.title = "Custom name" }
        try state.refresh(details: details(), connectionID: a, records: records([20, 22, 23]), language: nil)
        let edited = try #require(state.entry(id))
        #expect(state.title(edited) == "My edition")
        #expect(state.description(edited).isEmpty)
        #expect(edited.slots.first?.preferred?.edits.title == "Custom name")
        try state.resetDetails(id)
        #expect(state.entry(id)?.links.count == 2)
        #expect(state.entry(id)?.slots.count == 4)
    }
    @Test func removedChaptersStayExcluded() throws {
        var (state, id) = try mixed()
        let slot = try #require(state.entry(id)?.slots.first)
        try state.removeSlots(entryID: id, slotIDs: [slot.id])
        try state.refresh(details: details(), connectionID: a, records: records([20, 22]), language: nil)
        #expect(state.entry(id)?.slots.count == 2)
        #expect(state.entry(id)?.exclusions.count == 1)
        try state.validate(connections: [a, b], categories: [])
    }
    @Test func alternativesHaveIndependentPhysicalCompletion() throws {
        var (state, id) = try mixed()
        let incoming = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "20" })
        try state.copy([MCCopiedChapter(chapterID: incoming.id)])
        var choices = try state.pastePreview(entryID: id)
        #expect(choices[0].action == .unresolved)
        choices[0].action = .alternative
        try state.paste(entryID: id, revision: try #require(state.entry(id)).sequenceRevision, choices: choices)
        let slot = try #require(state.entry(id)?.slots.first)
        let original = try #require(slot.preferred).chapterID
        state.completed.insert(try #require(state.chapter(original)).identity)
        #expect(state.isRead(slot))
        try state.editEntry(id) { $0.slots[0].preferredID = $0.slots[0].variants[1].id }
        #expect(!state.isRead(try #require(state.entry(id)?.slots.first)))
    }
    @Test func stalePasteCannotOverwriteNewerEdits() throws {
        var (state, id) = try mixed()
        let copied = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "20" })
        try state.copy([MCCopiedChapter(chapterID: copied.id)])
        var choices = try state.pastePreview(entryID: id)
        choices[0].action = .alternative
        let revision = try #require(state.entry(id)).sequenceRevision
        try state.editEntry(id) { $0.titleOverride = "Newer edit" }
        #expect(throws: MCLibraryFailure.self) { try state.paste(entryID: id, revision: revision, choices: choices) }
        #expect(state.title(try #require(state.entry(id))) == "Newer edit")
        #expect(state.clipboard.count == 1)
    }
    @Test func manualOrderDoesNotReverseWhenDisplayIsDescending() throws {
        var (state, id) = try mixed()
        let last = try #require(state.entry(id)?.slots.last)
        try state.moveSlot(entryID: id, slotID: last.id, offset: -1)
        try state.editEntry(id) { $0.descendingDisplay = true }
        let entry = try #require(state.entry(id))
        #expect(entry.slots.compactMap(\.preferred).compactMap { state.number($0) } == ["20", "22", "21"])
    }
    @Test func pasteEditsPersistAndConsumeOnlyReviewedClipboard() throws {
        var state = MCLibraryState()
        let id = try state.add(details: details(), connectionID: a, records: records([1]), language: nil)
        _ = try state.remember(details: details(), connectionID: b, records: records([2, 3]), complete: true)
        let incoming = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "2" })
        try state.copy([MCCopiedChapter(chapterID: incoming.id)])
        var choices = try state.pastePreview(entryID: id)
        choices[0].item.edits.title = "My chapter"
        choices[0].item.edits.number = "1.5"
        choices[0].item.edits.volume = "2"
        try state.paste(entryID: id, revision: 0, choices: choices)
        #expect(state.clipboard.isEmpty)
        let reloaded = try JSONDecoder().decode(MCLibraryState.self, from: JSONEncoder().encode(state))
        let pasted = try #require(reloaded.entry(id)?.slots.last?.preferred)
        #expect(reloaded.chapterDisplayTitle(pasted) == "My chapter")
        #expect(pasted.edits.number == "1.5")
        #expect(pasted.edits.volume == "2")
        #expect(reloaded.chapter(pasted.chapterID)?.record.number == "2")
        try state.copy([MCCopiedChapter(chapterID: incoming.id)])
        let oldPreview = try state.pastePreview(entryID: id)
        let other = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "3" })
        try state.copy([MCCopiedChapter(chapterID: other.id)])
        try state.paste(entryID: id, revision: try #require(state.entry(id)).sequenceRevision, choices: oldPreview)
        #expect(state.clipboard.first?.chapterID == other.id)
    }

    @Test func resetEntryAndChapterAreIndependent() throws {
        var (state, id) = try mixed()
        let first = try #require(state.entry(id)?.slots.first)
        try state.editEntry(id) { entry in
            entry.titleOverride = "Custom entry"
            entry.slots[0].variants[0].edits.title = "Custom chapter"
            entry.manualOrder = true
            entry.slots.reverse()
        }
        let order = try #require(state.entry(id)).slots.map(\.id)
        try state.resetDetails(id)
        let entry = try #require(state.entry(id))
        #expect(entry.slots.map(\.id) == order)
        #expect(entry.manualOrder)
        #expect(entry.slots.first(where: { $0.id == first.id })?.preferred?.edits.title == "Custom chapter")
        try state.editEntry(id) { $0.titleOverride = "Keep entry edit" }
        try state.resetChapterDetails(entryID: id, slotID: first.id)
        #expect(state.entry(id)?.slots.first(where: { $0.id == first.id })?.preferred?.edits.title == nil)
        #expect(state.entry(id)?.titleOverride == "Keep entry edit")
        #expect(state.entry(id)?.links.count == 2)
    }

    @Test func editedPasteNumberRechecksDuplicates() throws {
        var (state, id) = try mixed()
        let source = try #require(state.chapters.first { $0.identity.listing.connectionID == b && $0.record.number == "20" })
        let item = MCCopiedChapter(chapterID: source.id, edits: .init(number: "30"))
        let preview = try state.pastePreview(entryID: id, items: [item])
        #expect(preview[0].action == .separate)
        #expect(preview[0].targetSlotID == nil)
    }

}
