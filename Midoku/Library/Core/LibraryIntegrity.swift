import Foundation

nonisolated extension LibraryState {
    func validate(connections: Set<UUID>, categories: Set<UUID>) throws {
        func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
        guard entries.count <= 5000, listings.count <= 15_000, chapters.count <= 100_000,
              clipboard.count <= 5000, covers.count <= 5000, updates.count <= 1000,
              unique(entries.map(\.id)), unique(listings.map(\.id)), unique(listings.map(\.identity)),
              unique(chapters.map(\.id)), unique(chapters.map(\.identity)), unique(covers.map(\.id)), unique(clipboard.map(\.id)),
              unique(updates.map(\.id)) else { throw LibraryFailure.invalid }
        let listingKeys = Set(listings.map(\.identity)), chapterIDs = Set(chapters.map(\.id))
        let coverIDs = Set(covers.map(\.id)), listingIDs = Set(listings.map(\.id)), entryIDs = Set(entries.map(\.id))
        let allSlots = entries.flatMap(\.slots)
        guard unique(allSlots.map(\.id)), unique(allSlots.flatMap(\.variants).map(\.id)) else { throw LibraryFailure.invalid }
        for listing in listings {
            guard connections.contains(listing.identity.connectionID), !listing.identity.externalID.isEmpty,
                  listing.identity.externalID.count <= 2000, listing.details.id == listing.identity.externalID,
                  !listing.details.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  listing.details.title.count <= 1000, listing.details.description.count <= 100_000,
                  listing.refreshedAt?.timeIntervalSince1970.isFinite != false else { throw LibraryFailure.invalid }
        }
        for chapter in chapters {
            guard listingKeys.contains(chapter.identity.listing), !chapter.identity.externalID.isEmpty,
                  chapter.identity.externalID.count <= 2000, chapter.record.id == chapter.identity.externalID,
                  chapter.record.title.count <= 1000, (chapter.record.number?.count ?? 0) <= 100 else { throw LibraryFailure.invalid }
        }
        for cover in covers {
            guard !cover.data.isEmpty, cover.data.count <= 1_048_576,
                  cover.digest == LibraryCover.hash(cover.data),
                  cover.data.starts(with: [0xFF, 0xD8, 0xFF]) || cover.data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { throw LibraryFailure.cover }
        }
        func valid(_ edits: ChapterEdits) -> Bool {
            (edits.title?.count ?? 0) <= 1000 && (edits.number?.count ?? 0) <= 100 && (edits.volume?.count ?? 0) <= 100 &&
                (edits.coverID == nil || coverIDs.contains(edits.coverID ?? UUID()))
        }
        for entry in entries {
            guard !title(entry).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title(entry).count <= 1000,
                  description(entry).count <= 100_000, (entry.authorOverride?.count ?? 0) <= 4000,
                  entry.categoryIDs.isSubset(of: categories), entry.exclusions.isSubset(of: chapterIDs),
                  entry.coverID == nil || coverIDs.contains(entry.coverID ?? UUID()),
                  entry.primaryListingID == nil || entry.links.contains(where: { $0.listingID == entry.primaryListingID }),
                  unique(entry.links.map(\.id)), unique(entry.links.map(\.listingID)),
                  entry.links.allSatisfy({ listingIDs.contains($0.listingID) && ($0.followBaseline ?? []).isSubset(of: chapterIDs) }),
                  entry.createdAt.timeIntervalSince1970.isFinite, entry.updatedAt.timeIntervalSince1970.isFinite,
                  entry.lastReadAt?.timeIntervalSince1970.isFinite != false, entry.sequenceRevision >= 0 else { throw LibraryFailure.invalid }
            let memberships = entry.slots.flatMap(\.variants).map(\.chapterID)
            guard unique(memberships), Set(memberships).isSubset(of: chapterIDs), Set(memberships).isDisjoint(with: entry.exclusions) else { throw LibraryFailure.invalid }
            for slot in entry.slots {
                guard !slot.variants.isEmpty, slot.variants.contains(where: { $0.id == slot.preferredID }), slot.variants.allSatisfy({ valid($0.edits) }) else { throw LibraryFailure.invalid }
                for variant in slot.variants {
                    guard let source = chapter(variant.chapterID), let listing = listings.first(where: { $0.identity == source.identity.listing }), entry.links.contains(where: { $0.listingID == listing.id }) else { throw LibraryFailure.invalid }
                }
            }
            if let reader = entry.readerOverride {
                guard reader.brightness.isFinite, (0.05...1).contains(reader.brightness) else { throw LibraryFailure.invalid }
            }
        }
        guard clipboard.allSatisfy({ chapterIDs.contains($0.chapterID) && valid($0.edits) }),
              completed.allSatisfy({ connections.contains($0.listing.connectionID) && !$0.externalID.isEmpty && !$0.listing.externalID.isEmpty }),
              updates.allSatisfy({ entryIDs.contains($0.entryID) && chapterIDs.contains($0.chapterID) && $0.discoveredAt.timeIntervalSince1970.isFinite }) else { throw LibraryFailure.invalid }
    }

    /// Existing app-owned entries win; shared records map by exact source identity before references are copied.
    func merging(_ imported: LibraryState, categoryMap: [UUID: UUID]) throws -> LibraryState {
        var result = self
        var listingsMap: [UUID: UUID] = [:], chaptersMap: [UUID: UUID] = [:]
        for incoming in imported.listings {
            if let collision = listings.first(where: { $0.id == incoming.id }), collision.identity != incoming.identity { throw LibraryFailure.invalid }
            if let local = result.listings.first(where: { $0.identity == incoming.identity }) { listingsMap[incoming.id] = local.id }
            else { result.listings.append(incoming); listingsMap[incoming.id] = incoming.id }
        }
        for incoming in imported.chapters {
            if let collision = chapters.first(where: { $0.id == incoming.id }), collision.identity != incoming.identity { throw LibraryFailure.invalid }
            if let local = result.chapters.first(where: { $0.identity == incoming.identity }) { chaptersMap[incoming.id] = local.id }
            else { result.chapters.append(incoming); chaptersMap[incoming.id] = incoming.id }
        }
        for incoming in imported.covers {
            if let local = covers.first(where: { $0.id == incoming.id }) {
                guard local.digest == incoming.digest else { throw LibraryFailure.invalid }
            } else { result.covers.append(incoming) }
        }
        for var incoming in imported.entries where !entries.contains(where: { $0.id == incoming.id }) {
            incoming.primaryListingID = incoming.primaryListingID.flatMap { listingsMap[$0] }
            incoming.categoryIDs = Set(incoming.categoryIDs.compactMap { categoryMap[$0] })
            for index in incoming.links.indices {
                incoming.links[index].listingID = listingsMap[incoming.links[index].listingID] ?? incoming.links[index].listingID
                incoming.links[index].followBaseline = incoming.links[index].followBaseline.map { Set($0.compactMap { chaptersMap[$0] }) }
            }
            for slot in incoming.slots.indices {
                for variant in incoming.slots[slot].variants.indices {
                    let id = incoming.slots[slot].variants[variant].chapterID
                    incoming.slots[slot].variants[variant].chapterID = chaptersMap[id] ?? id
                }
            }
            incoming.exclusions = Set(incoming.exclusions.compactMap { chaptersMap[$0] })
            result.entries.append(incoming)
        }
        if result.clipboard.isEmpty {
            result.clipboard = imported.clipboard.map { var item = $0; item.chapterID = chaptersMap[item.chapterID] ?? item.chapterID; return item }
        }
        let localPhysical = Set(chapters.map(\.identity))
        result.completed.formUnion(imported.completed.filter { !localPhysical.contains($0) })
        for var update in imported.updates where !result.updates.contains(where: { $0.id == update.id }) {
            update.chapterID = chaptersMap[update.chapterID] ?? update.chapterID
            if !result.updates.contains(where: { $0.entryID == update.entryID && $0.chapterID == update.chapterID }) { result.updates.append(update) }
        }
        result.updates = Array(result.updates.suffix(1000))
        return result
    }
}

nonisolated extension AppSnapshot {
    mutating func finished(_ identity: SourceChapterIdentity, entryID: UUID?, slotID: UUID?) {
        library.completed.insert(identity)
        if let entryID, let slotID, let index = library.entries.firstIndex(where: { $0.id == entryID }),
           let slot = library.entries[index].slots.firstIndex(where: { $0.id == slotID }) {
            library.entries[index].slots[slot].completionOverride = nil
        }
    }

    mutating func markSlots(entryID: UUID, slots: Set<UUID>, read: Bool) throws {
        guard let entry = library.entry(entryID) else { throw LibraryFailure.missing }
        for slot in entry.slots where slots.contains(slot.id) {
            if let variant = slot.preferred, let source = library.chapter(variant.chapterID) {
                if read { library.completed.insert(source.identity) }
                else { library.completed.remove(source.identity); progress.removeAll { $0.id == source.identity } }
            }
        }
        try library.editEntry(entryID) { entry in
            for index in entry.slots.indices where slots.contains(entry.slots[index].id) { entry.slots[index].completionOverride = nil }
        }
    }
}
