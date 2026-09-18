import Foundation
import Testing
@testable import MidokuExtensions

private func page(_ ids: [String], next: String? = nil) -> SourcePage<MangaSummary> {
    SourcePage(items: ids.map { MangaSummary(id: $0, title: $0, coverURL: nil) }, nextCursor: next)
}

private actor PageGate {
    private var continuation: CheckedContinuation<SourcePage<MangaSummary>, Never>?

    func fetch() async -> SourcePage<MangaSummary> {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while continuation == nil { await Task.yield() }
    }

    func complete(_ value: SourcePage<MangaSummary>) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@Suite("Source browsing state", .timeLimit(.minutes(1)))
@MainActor
struct SourceBrowsingTests {
    @Test func olderSearchCannotReplaceANewerResultEvenIfItIgnoresCancellation() async {
        let store = SourcePageStore<MangaSummary>()
        let gate = PageGate()
        let old = Task { await store.replace { await gate.fetch() } }
        await gate.waitUntilRequested()
        await store.replace { page(["new"]) }
        await gate.complete(page(["old"]))
        await old.value
        #expect(store.items.map(\.id) == ["new"])
        #expect(!store.isLoading)
        #expect(!store.isStale)
    }

    @Test func paginationCannotAppendToAnotherFeedOrFilterSelection() async {
        let store = SourcePageStore<MangaSummary>()
        await store.replace { page(["popular"], next: "20") }
        let gate = PageGate()
        let pagination = Task { await store.loadMore { _ in await gate.fetch() } }
        await gate.waitUntilRequested()
        await store.replace { page(["latest"]) }
        await gate.complete(page(["more-popular"], next: "40"))
        await pagination.value
        #expect(store.items.map(\.id) == ["latest"])
        #expect(store.nextCursor == nil)
        #expect(!store.isLoading)
    }

    @Test func paginationDeduplicatesMovingFeedsAndRejectsCursorLoops() async {
        let store = SourcePageStore<MangaSummary>()
        await store.replace { page(["a"], next: "20") }
        await store.loadMore { _ in page(["a", "b"], next: "40") }
        #expect(store.items.map(\.id) == ["a", "b"])
        await store.loadMore { _ in page(["c"], next: "20") }
        #expect(store.items.map(\.id) == ["a", "b"])
        #expect(store.errorMessage != nil)
        #expect(!store.isLoading)
    }

    @Test func cancellationAlwaysStopsTheLoadingIndicator() async {
        let store = SourcePageStore<MangaSummary>()
        let task = Task {
            await store.replace {
                try await Task.sleep(for: .seconds(60))
                return page(["cancelled"])
            }
        }
        while !store.isLoading { await Task.yield() }
        task.cancel()
        await task.value
        #expect(!store.isLoading)
        #expect(store.items.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test func failedRefreshPreservesContentAndCanBeRetried() async {
        let store = SourcePageStore<MangaSummary>()
        await store.replace { page(["saved"]) }
        await store.replace { throw ExtensionFailure.httpStatus(503) }
        #expect(store.items.map(\.id) == ["saved"])
        #expect(store.isStale)
        #expect(store.errorMessage != nil)
        #expect(!store.isLoading)
        await store.replace { page(["fresh"]) }
        #expect(store.items.map(\.id) == ["fresh"])
        #expect(!store.isStale)
        #expect(store.errorMessage == nil)
    }
}

nonisolated private final class ChunkedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "transport.example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/pending" { return } // Cancellation must complete even without a response.
        let length = url.path == "/declared-large" ? "10000" : nil
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: length.map { ["Content-Length": $0] }) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for _ in 0..<4 { client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 256)) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Bounded HTTP transport", .timeLimit(.minutes(1)))
struct SourceTransportTests {
    @Test func chunksAreCollectedAndBothDeclaredAndActualLengthsAreBounded() async throws {
        let transport = URLSessionSourceTransport(protocolClasses: [ChunkedProtocol.self])
        let url = try #require(URL(string: "https://transport.example.com/chunks"))
        let response = try await transport.send(URLRequest(url: url), maximumBytes: 1024)
        #expect(response.body == Data(repeating: 65, count: 1024))
        await #expect(throws: ExtensionFailure.responseTooLarge) {
            try await transport.send(URLRequest(url: url), maximumBytes: 1023)
        }
        let oversized = try #require(URL(string: "https://transport.example.com/declared-large"))
        await #expect(throws: ExtensionFailure.responseTooLarge) {
            try await transport.send(URLRequest(url: oversized), maximumBytes: 1024)
        }
    }

    @Test func cancelledTransferResumesExactlyOnceWithoutWaitingForTheServer() async throws {
        let transport = URLSessionSourceTransport(protocolClasses: [ChunkedProtocol.self])
        let url = try #require(URL(string: "https://transport.example.com/pending"))
        let task = Task { try await transport.send(URLRequest(url: url), maximumBytes: 1024) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
