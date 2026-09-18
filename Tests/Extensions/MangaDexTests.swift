import Foundation
import Testing
@testable import MidokuExtensions

private let fixtureMangaID = "00000001-1111-4111-8111-000000000001"
private let fixtureChapterID = "00000003-1111-4111-8111-000000000003"

private actor MangaDexFixtureHost: ExtensionHost {
    private var fixtures: [String]
    private let policy: SourceRequestPolicy
    private(set) var requests: [SourceHTTPRequest] = []

    init(fixtures: [String], manifest: ExtensionManifest) {
        self.fixtures = fixtures
        policy = SourceRequestPolicy(domains: manifest.domains)
    }

    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse {
        try policy.validate(input.url)
        try policy.validate(headers: input.headers)
        requests.append(input)
        guard !fixtures.isEmpty else { throw ExtensionFailure.invalidResponse("Unexpected fixture request") }
        let name = fixtures.removeFirst()
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/mangadex"))
        return SourceHTTPResponse(url: input.url, status: 200, headers: ["content-type": "application/json"], body: try Data(contentsOf: url))
    }
}

@Suite("Bundled MangaDex")
struct MangaDexTests {
    @Test func shippedBundleExecutesEveryCapabilityThroughJavaScriptCore() async throws {
        let resource = try #require(BundledExtensionResources.entries.first)
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(resource.manifestJSON.utf8))
        #expect(manifest.id == "dev.midoku.mangadex")
        #expect(manifest.capabilities == [.search, .feeds, .details, .chapters, .pages])
        let registry = ExtensionRegistry()
        try await registry.registerBundled(manifest: manifest, javaScript: resource.javaScript)
        let host = MangaDexFixtureHost(fixtures: ["search", "search", "details", "chapters", "chapter", "pages"], manifest: manifest)
        let connection = SourceConnection(extensionID: manifest.id, name: manifest.name)
        let adapter = try await registry.adapter(for: connection, host: host)

        let search = try await adapter.search(query: "Test & Atlas", cursor: nil)
        #expect(search.items.first?.id == fixtureMangaID)
        #expect(search.items.first?.title == "The Test Atlas")
        #expect(search.nextCursor == "20")
        #expect(try await adapter.feeds().map(\.id) == ["latest", "popular", "recent"])
        #expect(try await adapter.feed(id: "popular", cursor: nil).items.count == 2)
        let details = try await adapter.details(mangaID: fixtureMangaID)
        #expect(details.description == "Synthetic API fixture for Midoku.")
        let chapters = try await adapter.chapters(mangaID: fixtureMangaID, cursor: nil)
        #expect(chapters.items.map(\.number) == ["20.5", "20.5", nil])
        #expect(chapters.items.map(\.ordinal) == [0, 1, 4])
        #expect(chapters.nextCursor == "100")
        let pages = try await adapter.pages(mangaID: fixtureMangaID, chapterID: fixtureChapterID)
        #expect(pages.map(\.id) == [fixtureChapterID + ":1", fixtureChapterID + ":2"])
        #expect(pages.first?.url.absoluteString == "https://node-a.region.mangadex.network/token/data/fixture-hash/1-first.jpg")
        #expect(pages.first?.headers["Referer"] == "https://mangadex.org/")
        let requests = await host.requests
        #expect(requests.count == 6)
        #expect(requests.first?.url.absoluteString.contains("Test%20%26%20Atlas") == true)
        #expect(requests.last?.url.query == "forcePort443=true")
    }

    @Test func scopedSubdomainPermissionsRespectHostBoundariesAndExactDomainsStayExact() throws {
        let policy = SourceRequestPolicy(domains: ["*.mangadex.network", "uploads.mangadex.org"])
        for address in ["https://node.mangadex.network/data/1.jpg", "https://node.region.mangadex.network:443/data/1.jpg", "https://uploads.mangadex.org/covers/1.jpg"] {
            try policy.validate(try #require(URL(string: address)))
        }
        for address in [
            "https://mangadex.network/1.jpg", "https://badmangadex.network/1.jpg",
            "https://node.mangadex.network.evil.org/1.jpg", "https://node.mangadex.network@evil.org/1.jpg",
            "https://child.uploads.mangadex.org/1.jpg", "http://node.mangadex.network/1.jpg",
            "https://node.mangadex.network:8443/1.jpg", "https://127.0.0.1/1.jpg"
        ] {
            let url = try #require(URL(string: address))
            #expect(throws: ExtensionFailure.requestNotAllowed) { try policy.validate(url) }
        }
        for permission in ["*", "*.com", "*.*.example.com", "foo*.example.com", "*.127.0.0.1", "*.example.local", "*.Example.com"] {
            #expect(!SourceRequestPolicy.isDomainPermission(permission))
        }
    }

    @Test func generatedManifestAndBundleMatchAuthoringArtifacts() throws {
        // Guards against forgetting to regenerate the app's checked-in resources after source changes.
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = tests.deletingLastPathComponent().deletingLastPathComponent()
        let sourceManifest = root.appending(path: "Extensions/sources/dev.midoku.mangadex/manifest.json")
        let expected = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: sourceManifest))
        let resource = try #require(BundledExtensionResources.entries.first)
        let embedded = try JSONDecoder().decode(ExtensionManifest.self, from: Data(resource.manifestJSON.utf8))
        #expect(embedded == expected)
        // dist is optional in a Node-free checkout; when present it must agree byte-for-byte.
        let built = root.appending(path: "Extensions/dist/dev.midoku.mangadex/bundle.js")
        if FileManager.default.fileExists(atPath: built.path) {
            #expect(try String(contentsOf: built, encoding: .utf8) == resource.javaScript)
        }
    }
}
