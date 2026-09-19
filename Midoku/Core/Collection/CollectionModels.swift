import Foundation
import CryptoKit

nonisolated enum MCPersonalStatus: String, MCSettingChoice {
    case planned, reading, completed, onHold, dropped
    var title: String { self == .onHold ? "On hold" : rawValue.capitalized }
}

nonisolated struct MCLibraryListing: Codable, Identifiable, Sendable {
    var id = UUID()
    let identity: MCSourceListingIdentity
    var details: MCMangaDetails
    var refreshedAt: Date?
    var lastError: String?
}

nonisolated struct MCLibraryChapter: Codable, Identifiable, Sendable {
    var id = UUID()
    let identity: MCSourceChapterIdentity
    var record: MCChapterRecord
    var available = true
}

nonisolated struct MCEntrySourceLink: Codable, Identifiable, Sendable {
    var id = UUID()
    var listingID: UUID
    var followsNewChapters: Bool
    var language: String?
    var followBaseline: Set<UUID>? = nil
    // A partial initial add still imports the existing catalogue when following is off.
    var needsInitialImport: Bool? = nil
}

/// nil inherits; an empty string deliberately clears a field. Source records never change.
nonisolated struct MCChapterEdits: Codable, Sendable {
    var title: String?
    var number: String?
    var volume: String?
    var coverID: UUID?
}

nonisolated struct MCChapterVariant: Codable, Identifiable, Sendable {
    var id = UUID()
    var chapterID: UUID
    var edits = MCChapterEdits()
}

nonisolated struct MCChapterSlot: Codable, Identifiable, Sendable {
    var id = UUID()
    var variants: [MCChapterVariant]
    var preferredID: UUID
    var completionOverride: Bool?
    var preferred: MCChapterVariant? { variants.first { $0.id == preferredID } }
    init(variant: MCChapterVariant) { variants = [variant]; preferredID = variant.id }
}

nonisolated struct MCPersonalEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var lastReadAt: Date?
    var titleOverride: String?
    var descriptionOverride: String?
    var authorOverride: String?
    var coverID: UUID?
    var hidesCover = false
    var primaryListingID: UUID?
    var status = MCPersonalStatus.planned
    var categoryIDs: Set<UUID> = []
    var links: [MCEntrySourceLink] = []
    var slots: [MCChapterSlot] = []
    var exclusions: Set<UUID> = []
    var manualOrder = false
    var sequenceRevision = 0
    var readerOverride: MCReaderPreferences?
    var descendingDisplay = false
}

nonisolated struct MCCopiedChapter: Codable, Identifiable, Sendable {
    var id: UUID { chapterID }
    var chapterID: UUID
    var edits = MCChapterEdits()
}

/// Bounded, normalized JPEG/PNG bytes travel with the transactional backup; no arbitrary paths.
nonisolated struct MCLibraryCover: Codable, Identifiable, Sendable {
    var id = UUID()
    var data: Data
    var digest: String
    init(data: Data) {
        self.data = data
        digest = Self.hash(data)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

nonisolated struct MCLibraryUpdate: Codable, Identifiable, Sendable {
    var id = UUID()
    var entryID: UUID
    var chapterID: UUID
    var discoveredAt = Date()
}

nonisolated enum MCPasteAction: String, CaseIterable, Identifiable, Sendable {
    case unresolved, skip, separate, alternative, replace
    var id: String { rawValue }
    var title: String {
        switch self { case .unresolved: "Choose…"; case .skip: "Skip"; case .separate: "Keep separate"; case .alternative: "Keep alternative"; case .replace: "Replace existing" }
    }
}

nonisolated struct MCPasteChoice: Identifiable, Sendable {
    var id: UUID { item.chapterID }
    var item: MCCopiedChapter
    var action: MCPasteAction
    var targetSlotID: UUID?
    var restoreExcluded = false
    var preserveCompletion = false
}

nonisolated struct MCLibraryState: Codable, Sendable {
    var entries: [MCPersonalEntry] = []
    var listings: [MCLibraryListing] = []
    var chapters: [MCLibraryChapter] = []
    var covers: [MCLibraryCover] = []
    var clipboard: [MCCopiedChapter] = []
    var completed: Set<MCSourceChapterIdentity> = []
    var updates: [MCLibraryUpdate] = []

    func entry(_ id: UUID) -> MCPersonalEntry? { entries.first { $0.id == id } }
    func listing(_ id: UUID?) -> MCLibraryListing? { listings.first { $0.id == id } }
    func chapter(_ id: UUID) -> MCLibraryChapter? { chapters.first { $0.id == id } }
    func title(_ entry: MCPersonalEntry) -> String { entry.titleOverride ?? listing(entry.primaryListingID)?.details.title ?? "Untitled entry" }
    func description(_ entry: MCPersonalEntry) -> String { entry.descriptionOverride ?? listing(entry.primaryListingID)?.details.description ?? "" }
    func number(_ variant: MCChapterVariant) -> String? { variant.edits.number ?? chapter(variant.chapterID)?.record.number }
    func chapterTitle(_ variant: MCChapterVariant) -> String { variant.edits.title ?? chapter(variant.chapterID)?.record.title ?? "Unavailable chapter" }
    func chapterDisplayTitle(_ variant: MCChapterVariant) -> String {
        if let title = variant.edits.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return number(variant).flatMap { $0.isEmpty ? nil : "Chapter \($0)" } ?? chapterTitle(variant)
    }
    func isRead(_ slot: MCChapterSlot) -> Bool {
        if let override = slot.completionOverride { return override }
        guard let variant = slot.preferred, let source = chapter(variant.chapterID) else { return false }
        return completed.contains(source.identity)
    }
    func readerContext(identity: MCSourceChapterIdentity, preferredEntryID: UUID? = nil) -> (entryID: UUID, slotID: UUID)? {
        let ordered = entries.sorted { ($0.id == preferredEntryID ? 0 : 1) < ($1.id == preferredEntryID ? 0 : 1) }
        for entry in ordered {
            if let slot = entry.slots.first(where: { $0.preferred.flatMap { chapter($0.chapterID) }?.identity == identity }) {
                return (entry.id, slot.id)
            }
        }
        return nil
    }
    func resumeSlot(_ entry: MCPersonalEntry, positions: [MCReadingPosition]) -> UUID? {
        if let recent = positions.sorted(by: { $0.updatedAt > $1.updatedAt }).first(where: { position in
            entry.slots.contains { slot in slot.preferred.flatMap { chapter($0.chapterID) }?.identity == position.id && !isRead(slot) }
        }), let slot = entry.slots.first(where: { $0.preferred.flatMap { chapter($0.chapterID) }?.identity == recent.id }) { return slot.id }
        return entry.slots.first(where: { !isRead($0) })?.id ?? entry.slots.first?.id
    }

    @discardableResult
    mutating func remember(details: MCMangaDetails, connectionID: UUID, records: [MCChapterRecord], complete: Bool, language: String? = nil) throws -> UUID {
        let identity = MCSourceListingIdentity(connectionID: connectionID, externalID: details.id)
        guard Set(records.map(\.id)).count == records.count else { throw MCLibraryFailure.invalid }
        let listingID: UUID
        if let index = listings.firstIndex(where: { $0.identity == identity }) {
            listings[index].details = details
            if complete { listings[index].refreshedAt = Date(); listings[index].lastError = nil }
            listingID = listings[index].id
        } else {
            var listing = MCLibraryListing(identity: identity, details: details)
            if complete { listing.refreshedAt = Date() }
            listingID = listing.id; listings.append(listing)
        }
        let incoming = Set(records.map(\.id))
        if complete {
            for index in chapters.indices where chapters[index].identity.listing == identity && (language == nil || chapters[index].record.language == language) {
                chapters[index].available = incoming.contains(chapters[index].record.id)
            }
        }
        for record in records {
            let key = MCSourceChapterIdentity(listing: identity, externalID: record.id)
            if let index = chapters.firstIndex(where: { $0.identity == key }) {
                chapters[index].record = record; chapters[index].available = true
            } else { chapters.append(MCLibraryChapter(identity: key, record: record)) }
        }
        return listingID
    }

    @discardableResult
    mutating func add(details: MCMangaDetails, connectionID: UUID, records: [MCChapterRecord], language: String?, categories: Set<UUID> = [], complete: Bool = true,
                      status: MCPersonalStatus = .planned, followsNewChapters: Bool = true) throws -> UUID {
        let listingID = try remember(details: details, connectionID: connectionID, records: records, complete: complete, language: language)
        if let existing = entries.first(where: { $0.links.contains { $0.listingID == listingID } }) { return existing.id }
        var entry = MCPersonalEntry()
        entry.primaryListingID = listingID; entry.categoryIDs = categories
        entry.links = [MCEntrySourceLink(listingID: listingID, followsNewChapters: followsNewChapters,
            language: language, needsInitialImport: !complete)]
        entry.status = status
        let keys = Set(records.map(\.id))
        entry.slots = chapters.filter { $0.identity.listing == listing(listingID)?.identity && keys.contains($0.record.id) }
            .map { MCChapterSlot(variant: MCChapterVariant(chapterID: $0.id)) }
        sortSequence(&entry)
        entries.append(entry)
        return entry.id
    }

    /// Reset presentation overrides without rebuilding or discarding the mixed-source composition.
    mutating func resetDetails(_ id: UUID) throws {
        try editEntry(id) { entry in
            if let original = entry.links.first?.listingID {
                entry.primaryListingID = original
                entry.titleOverride = nil; entry.descriptionOverride = nil; entry.authorOverride = nil
            }
            entry.coverID = nil; entry.hidesCover = false
            entry.readerOverride = nil; entry.manualOrder = false; entry.descendingDisplay = false
            for slot in entry.slots.indices {
                for variant in entry.slots[slot].variants.indices { entry.slots[slot].variants[variant].edits = MCChapterEdits() }
            }
        }
    }

    @discardableResult
    mutating func createManual(title: String, description: String = "", categories: Set<UUID> = []) throws -> UUID {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 1000 else { throw MCLibraryFailure.emptyTitle }
        var entry = MCPersonalEntry(); entry.titleOverride = title; entry.descriptionOverride = description; entry.categoryIDs = categories
        entries.append(entry); return entry.id
    }

    mutating func editEntry(_ id: UUID, _ edit: (inout MCPersonalEntry) throws -> Void) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw MCLibraryFailure.missing }
        var candidate = entries[index]; try edit(&candidate)
        candidate.updatedAt = Date(); candidate.sequenceRevision += 1
        if !candidate.manualOrder { sortSequence(&candidate) }
        entries[index] = candidate
    }

    mutating func refresh(details: MCMangaDetails, connectionID: UUID, records: [MCChapterRecord], language: String?) throws {
        let listingID = try remember(details: details, connectionID: connectionID, records: records, complete: true, language: language)
        let identity = MCSourceListingIdentity(connectionID: connectionID, externalID: details.id)
        let incoming = chapters.filter { $0.identity.listing == identity && $0.available && (language == nil || $0.record.language == language) }
        for index in entries.indices {
            guard let link = entries[index].links.first(where: { $0.listingID == listingID }),
                  (link.followsNewChapters || link.needsInitialImport == true), link.language == language else { continue }
            var entry = entries[index]
            let present = Set(entry.slots.flatMap(\.variants).map(\.chapterID))
            let additions = incoming.filter { !present.contains($0.id) && !entry.exclusions.contains($0.id) && !(link.followBaseline ?? []).contains($0.id) }
            // Equal numbers stay separate; grouping always requires explicit equivalence confirmation.
            for item in additions {
                entry.slots.append(MCChapterSlot(variant: MCChapterVariant(chapterID: item.id)))
                if link.needsInitialImport != true, !updates.contains(where: { $0.entryID == entry.id && $0.chapterID == item.id }) {
                    updates.append(MCLibraryUpdate(entryID: entry.id, chapterID: item.id))
                }
            }
            if let linkIndex = entry.links.firstIndex(where: { $0.id == link.id }), entry.links[linkIndex].followBaseline != nil {
                entry.links[linkIndex].followBaseline?.formUnion(incoming.map(\.id))
            }
            if let linkIndex = entry.links.firstIndex(where: { $0.id == link.id }) { entry.links[linkIndex].needsInitialImport = false }
            if !entry.manualOrder { sortSequence(&entry) }
            entry.sequenceRevision += 1
            if !additions.isEmpty { entry.updatedAt = Date() }
            entries[index] = entry
        }
        updates = Array(updates.suffix(1000))
    }

    mutating func copy(_ items: [MCCopiedChapter]) throws {
        guard !items.isEmpty, items.count <= 5000, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ chapter($0.chapterID) != nil }) else { throw MCLibraryFailure.invalid }
        clipboard = items
    }

    func pastePreview(entryID: UUID) throws -> [MCPasteChoice] {
        guard let entry = entry(entryID) else { throw MCLibraryFailure.missing }
        let existing = Set(entry.slots.flatMap(\.variants).map(\.chapterID))
        return clipboard.map { item in
            let incoming = MCChapterVariant(chapterID: item.chapterID, edits: item.edits)
            let match = entry.slots.first { slot in
                guard let variant = slot.preferred, let lhs = number(variant), let rhs = number(incoming), !lhs.isEmpty, !rhs.isEmpty else { return false }
                return Self.sameNumber(lhs, rhs)
            }
            return MCPasteChoice(item: item, action: existing.contains(item.chapterID) ? .skip : (match == nil ? .separate : .unresolved), targetSlotID: match?.id)
        }
    }

    mutating func paste(entryID: UUID, revision: Int, choices: [MCPasteChoice], insertBefore: UUID? = nil) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { throw MCLibraryFailure.missing }
        guard entries[index].sequenceRevision == revision else { throw MCLibraryFailure.stalePreview }
        guard Set(choices.map(\.id)).count == choices.count, choices.allSatisfy({ $0.action != .unresolved }) else { throw MCLibraryFailure.unresolved }
        var candidate = self
        var entry = candidate.entries[index]
        for choice in choices where choice.action != .skip {
            guard let source = chapter(choice.item.chapterID), let listing = listings.first(where: { $0.identity == source.identity.listing }) else { throw MCLibraryFailure.missing }
            if entry.slots.flatMap(\.variants).contains(where: { $0.chapterID == source.id }) { continue }
            guard !entry.exclusions.contains(source.id) || choice.restoreExcluded else { throw MCLibraryFailure.excluded }
            entry.exclusions.remove(source.id)
            if !entry.links.contains(where: { $0.listingID == listing.id }) {
                entry.links.append(MCEntrySourceLink(listingID: listing.id, followsNewChapters: false, language: source.record.language))
            }
            let variant = MCChapterVariant(chapterID: source.id, edits: choice.item.edits)
            switch choice.action {
            case .alternative, .replace:
                guard let slotIndex = entry.slots.firstIndex(where: { $0.id == choice.targetSlotID }) else { throw MCLibraryFailure.stalePreview }
                let wasRead = isRead(entry.slots[slotIndex])
                if choice.action == .replace {
                    entry.exclusions.formUnion(entry.slots[slotIndex].variants.map(\.chapterID))
                    entry.slots[slotIndex].variants = [variant]
                    entry.slots[slotIndex].preferredID = variant.id
                    entry.slots[slotIndex].completionOverride = choice.preserveCompletion && wasRead ? true : nil
                } else { entry.slots[slotIndex].variants.append(variant) }
            case .separate:
                let slot = MCChapterSlot(variant: variant)
                if let insertBefore, let position = entry.slots.firstIndex(where: { $0.id == insertBefore }) {
                    entry.slots.insert(slot, at: position); entry.manualOrder = true
                } else { entry.slots.append(slot) }
            case .skip, .unresolved: break
            }
        }
        entry.sequenceRevision += 1; entry.updatedAt = Date()
        if !entry.manualOrder { candidate.sortSequence(&entry) }
        candidate.entries[index] = entry
        self = candidate
    }

    mutating func removeSlots(entryID: UUID, slotIDs: Set<UUID>) throws {
        try editEntry(entryID) { entry in
            entry.exclusions.formUnion(entry.slots.filter { slotIDs.contains($0.id) }.flatMap(\.variants).map(\.chapterID))
            entry.slots.removeAll { slotIDs.contains($0.id) }
        }
    }
    mutating func restoreChapter(entryID: UUID, chapterID: UUID) throws {
        guard chapter(chapterID) != nil else { throw MCLibraryFailure.missing }
        try editEntry(entryID) { entry in
            entry.exclusions.remove(chapterID)
            if !entry.slots.flatMap(\.variants).contains(where: { $0.chapterID == chapterID }) {
                entry.slots.append(MCChapterSlot(variant: MCChapterVariant(chapterID: chapterID)))
            }
        }
    }
    mutating func moveSlot(entryID: UUID, slotID: UUID, offset: Int) throws {
        try editEntry(entryID) { entry in
            guard let index = entry.slots.firstIndex(where: { $0.id == slotID }), entry.slots.indices.contains(index + offset) else { return }
            entry.manualOrder = true; entry.slots.swapAt(index, index + offset)
        }
    }
    mutating func removeEntries(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        updates.removeAll { ids.contains($0.entryID) }
        // Shared physical records, downloads, History and progress deliberately survive.
    }

    func sortSequence(_ entry: inout MCPersonalEntry) {
        let positions = Dictionary(uniqueKeysWithValues: entry.slots.enumerated().map { ($0.element.id, $0.offset) })
        entry.slots.sort { lhs, rhs in
            guard let left = lhs.preferred, let right = rhs.preferred else { return lhs.id.uuidString < rhs.id.uuidString }
            let ln = number(left) ?? "", rn = number(right) ?? ""
            let a = Self.numeric(ln), b = Self.numeric(rn)
            if let a, let b, a != b { return a < b }
            if (a != nil) != (b != nil) { return a != nil }
            if a == nil && b == nil && ln != rn {
                let order = ln.compare(rn, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                if order != .orderedSame { return order == .orderedAscending }
            }
            return (positions[lhs.id] ?? 0) < (positions[rhs.id] ?? 0)
        }
    }
    static func numeric(_ value: String) -> Decimal? {
        guard value.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func sameNumber(_ lhs: String, _ rhs: String) -> Bool {
        if let a = numeric(lhs), let b = numeric(rhs) { return a == b }
        return lhs == rhs
    }

}

nonisolated enum MCLibraryFailure: Error, LocalizedError {
    case missing, invalid, emptyTitle, stalePreview, unresolved, excluded, incomplete, cover
    var errorDescription: String? {
        switch self {
        case .missing: "This item is no longer available. Reopen the entry and try again."
        case .invalid: "The library contains invalid or conflicting references. No changes were saved."
        case .emptyTitle: "Enter a title between 1 and 1,000 characters."
        case .stalePreview: "This entry changed while the preview was open. Close it and review the chapters again."
        case .unresolved: "Choose how to handle every possible duplicate before pasting."
        case .excluded: "Confirm that you want to restore the previously removed chapter."
        case .incomplete: "The source did not return a complete chapter list. Existing chapters are kept; try again."
        case .cover: "Choose a valid image under 20 MB. The previous cover has been kept."
        }
    }
}
