import Foundation

nonisolated enum ReaderPrefetchWindow {
    /// Physical page order is unchanged by RTL display. Never includes the visible page.
    static func indices(after index: Int, pageCount: Int) -> Range<Int> {
        guard pageCount > 0, index >= 0, index < pageCount else { return 0..<0 }
        let start = index + 1
        return start..<(start + min(5, pageCount - start))
    }

    static func load(_ pages: [PageResource], after index: Int,
                     using loader: @Sendable (PageResource) async throws -> Void) async {
        for next in indices(after: index, pageCount: pages.count) {
            guard !Task.isCancelled else { return }
            do { try await loader(pages[next]) }
            catch is CancellationError { return }
            catch { /* A failed speculative page remains retryable when actually opened. */ }
        }
    }
}
