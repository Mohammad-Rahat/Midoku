import Foundation
import Observation

/// A replacement invalidates both an older search and any in-flight pagination.
@MainActor
@Observable
final class SourcePageStore<Item: Codable & Sendable & Identifiable> where Item.ID == String {
    private(set) var items: [Item] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isStale = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private var consumedCursors = Set<String>()

    func replace(using fetch: @Sendable () async throws -> SourcePage<Item>) async {
        let token = UUID()
        generation = token
        isLoading = true
        isStale = !items.isEmpty
        errorMessage = nil
        nextCursor = nil
        consumedCursors = []
        do {
            let page = try await fetch()
            try Task.checkCancellation()
            guard generation == token else { return }
            items = page.items
            nextCursor = page.nextCursor
            isStale = false
        } catch {
            guard generation == token else { return }
            if !Task.isCancelled {
                errorMessage = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription
            }
        }
        if generation == token { isLoading = false }
    }

    func loadMore(using fetch: @Sendable (String) async throws -> SourcePage<Item>) async {
        guard !isLoading, !isStale, let cursor = nextCursor else { return }
        let token = generation
        isLoading = true
        errorMessage = nil
        do {
            let page = try await fetch(cursor)
            try Task.checkCancellation()
            guard generation == token else { return }
            if let next = page.nextCursor, next == cursor || consumedCursors.contains(next) {
                throw ExtensionFailure.invalidResponse("The source repeated a pagination cursor.")
            }
            consumedCursors.insert(cursor)
            var seen = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            nextCursor = page.nextCursor
        } catch {
            guard generation == token else { return }
            if !Task.isCancelled {
                errorMessage = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription
            }
        }
        if generation == token { isLoading = false }
    }
}
