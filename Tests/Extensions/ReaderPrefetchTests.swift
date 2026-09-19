import Foundation
import Testing
@testable import MidokuExtensions

private actor PrefetchRecorder {
    var ids: [String] = []
    func append(_ id: String) { ids.append(id) }
}

@Suite("Reader preloading")
struct ReaderPrefetchTests {
    @Test func windowIsExactlyNextFiveAndClampsAtEnd() {
        #expect(Array(ReaderPrefetchWindow.indices(after: 0, pageCount: 20)) == [1, 2, 3, 4, 5])
        #expect(Array(ReaderPrefetchWindow.indices(after: 17, pageCount: 20)) == [18, 19])
        #expect(ReaderPrefetchWindow.indices(after: 19, pageCount: 20).isEmpty)
        #expect(ReaderPrefetchWindow.indices(after: -1, pageCount: 20).isEmpty)
        #expect(ReaderPrefetchWindow.indices(after: 0, pageCount: 0).isEmpty)
        #expect(ReaderPrefetchWindow.indices(after: Int.max, pageCount: 20).isEmpty)
        #expect(Array(ReaderPrefetchWindow.indices(after: Int.max - 2, pageCount: Int.max)) == [Int.max - 1])
    }

    @Test func failedPrefetchDoesNotPreventLaterPagesAndCancellationStopsWindow() async throws {
        let url = try #require(URL(string: "https://example.com/page.jpg"))
        let pages = (0..<10).map { PageResource(id: String($0), url: url, headers: [:]) }
        let recorder = PrefetchRecorder()
        await ReaderPrefetchWindow.load(pages, after: 0) { page in
            await recorder.append(page.id)
            if page.id == "2" { throw ExtensionFailure.httpStatus(503) }
        }
        #expect(await recorder.ids == ["1", "2", "3", "4", "5"])
        let cancelled = PrefetchRecorder()
        await ReaderPrefetchWindow.load(pages, after: 0) { page in
            await cancelled.append(page.id)
            throw CancellationError()
        }
        #expect(await cancelled.ids == ["1"])
    }

    @Test func temporaryPageCacheHasIndependentSizeLimitAndPreservesBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ImageDiskCache(directory: directory, maximumBytes: 8 * 1024 * 1024,
            lifetime: 60, maximumItemBytes: 4 * 1024 * 1024, fileExtension: "image")
        let data = Data(repeating: 42, count: 3 * 1024 * 1024)
        try cache.store(data, key: "connection/chapter/page")
        #expect(cache.read("connection/chapter/page") == data)
        #expect(cache.file(for: "connection/chapter/page").pathExtension == "image")
        try cache.store(Data(repeating: 5, count: 5 * 1024 * 1024), key: "too-large")
        #expect(cache.read("too-large") == nil)
        try cache.clear()
        #expect(cache.read("connection/chapter/page") == nil)
    }
}
