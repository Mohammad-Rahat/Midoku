import Foundation

/// Every cover write names its exact owner. Entry artwork is never chapter artwork.
nonisolated enum LibraryCoverTarget: Sendable {
    case entry(UUID)
    case chapter(entryID: UUID, slotID: UUID, variantID: UUID)
}

nonisolated extension LibraryState {
    mutating func setCover(_ cover: LibraryCover, for target: LibraryCoverTarget) throws {
        switch target {
        case .entry(let id):
            try editEntry(id) { $0.coverID = cover.id; $0.hidesCover = false }
        case .chapter(let entryID, let slotID, let variantID):
            try editEntry(entryID) { entry in
                guard let slot = entry.slots.firstIndex(where: { $0.id == slotID }),
                      let variant = entry.slots[slot].variants.firstIndex(where: { $0.id == variantID }) else {
                    throw LibraryFailure.stalePreview
                }
                entry.slots[slot].variants[variant].edits.coverID = cover.id
            }
        }
        if !covers.contains(where: { $0.id == cover.id }) { covers.append(cover) }
    }
}
