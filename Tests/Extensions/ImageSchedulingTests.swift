import Foundation
import Testing
@testable import MidokuExtensions

private actor ImageGate {
    var calls = 0
    var cancelled = 0
    var released = false
    func open() { released = true }
    func load() async throws -> Int {
        calls += 1
        do {
            while !released { try await Task.sleep(for: .milliseconds(5)) }
            return 7
        } catch { cancelled += 1; throw error }
    }
}

private actor PriorityTransport: SourceHTTPTransport {
    var paths: [String] = []
    var released = false
    func open() { released = true }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SourceHTTPResponse {
        let url = try #require(request.url)
        paths.append(url.path)
        while url.path == "/first" && !released { try await Task.sleep(for: .milliseconds(5)) }
        return SourceHTTPResponse(url: url, status: 200, headers: [:], body: Data([1]))
    }
}

@Suite("Image scheduling", .timeLimit(.minutes(1)))
struct ImageSchedulingTests {
    @Test func cancellingPrefetchKeepsSharedVisibleRequestAlive() async throws {
        let pool = SharedTaskPool<Int>()
        let gate = ImageGate()
        let first = Task { try await pool.value(for: "page") { try await gate.load() } }
        while await gate.calls == 0 { await Task.yield() }
        let visible = Task { try await pool.value(for: "page") { try await gate.load() } }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await gate.cancelled == 0)
        await gate.open()
        #expect(try await visible.value == 7)
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await gate.calls == 1)
    }

    @Test func abandonedRequestCancelsAndFailedRequestCanRetry() async throws {
        let pool = SharedTaskPool<Int>()
        let gate = ImageGate()
        let abandoned = Task { try await pool.value(for: "page") { try await gate.load() } }
        while await gate.calls == 0 { await Task.yield() }
        abandoned.cancel()
        await #expect(throws: CancellationError.self) { try await abandoned.value }
        #expect(await gate.cancelled == 1)
        await #expect(throws: ExtensionFailure.verificationRequired) {
            try await pool.value(for: "page") { throw ExtensionFailure.verificationRequired }
        }
        #expect(try await pool.value(for: "page") { 9 } == 9)
    }

    @Test func visiblePagesPrecedePrefetchAndThumbnailWork() async throws {
        let transport = PriorityTransport()
        let manifest = ExtensionManifest(id: "dev.midoku.tests", name: "Test", version: "1.0.0",
            contractVersion: 1, domains: ["example.com"], capabilities: [.pages])
        let connection = SourceConnection(extensionID: manifest.id, name: "Test")
        let coordinator = SourceRequestCoordinator(transport: transport, sessions: EmptySourceSession(),
            verification: UnavailableChallengeResolver(), minimumSpacing: .zero)
        func request(_ path: String, _ kind: SourceRequestKind) async throws {
            let url = try #require(URL(string: "https://example.com/" + path))
            _ = try await coordinator.request(SourceHTTPRequest(url: url, headers: [:]), connection: connection,
                manifest: manifest, interaction: .background, kind: kind)
        }
        let first = Task { try await request("first", .image) }
        while await transport.paths.isEmpty { await Task.yield() }
        let thumbnail = Task { try await request("thumbnail", .thumbnail) }
        let metadata = Task { try await request("background", .backgroundMetadata) }
        let prefetch = Task { try await request("prefetch", .prefetch) }
        let visible = Task { try await request("visible", .image) }
        try await Task.sleep(for: .milliseconds(100))
        await transport.open()
        try await first.value; try await thumbnail.value; try await metadata.value
        try await prefetch.value; try await visible.value
        #expect(await transport.paths == ["/first", "/visible", "/prefetch", "/background", "/thumbnail"])
    }
}
