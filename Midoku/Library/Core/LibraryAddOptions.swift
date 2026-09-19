import Foundation

nonisolated struct LibraryAddOptions: Equatable, Sendable {
    var categoryIDs: Set<UUID> = []
    var status: PersonalStatus = .planned
    var followsNewChapters = true
}
