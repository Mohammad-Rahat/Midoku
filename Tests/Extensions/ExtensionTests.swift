import Foundation
import Testing
@testable import MidokuExtensions

private func manifest(capabilities: Set<SourceCapability> = [.search]) -> ExtensionManifest {
    ExtensionManifest(
        id: "dev.midoku.tests", name: "Test source", version: "1.0.0",
        contractVersion: 1, domains: ["example.com"], capabilities: capabilities
    )
}

private actor StubTransport: SourceHTTPTransport {
    var requests: [URLRequest] = []
    var responses: [SourceHTTPResponse]

    init(_ responses: [SourceHTTPResponse]) { self.responses = responses }

    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SourceHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ExtensionFailure.invalidResponse("Unexpected request") }
        return responses.removeFirst()
    }
}

private actor StubSession: SourceSessionProviding {
    var verified = false
    var received = 0

    func headers(for url: URL, connectionID: UUID) async throws -> [String: String] {
        verified ? ["Cookie": "clearance=fixture", "User-Agent": "FixtureBrowser"] : ["User-Agent": "FixtureBrowser"]
    }

    func receive(_ response: SourceHTTPResponse, connectionID: UUID) async throws { received += 1 }
    func verify() { verified = true }
}

private actor StubResolver: ChallengeResolving {
    var count = 0
    let session: StubSession

    init(session: StubSession) { self.session = session }
    func resolve(_ challenge: SourceChallenge) async throws {
        count += 1
        await session.verify()
    }
}

private struct RejectNetwork: ExtensionHost {
    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse {
        throw ExtensionFailure.requestNotAllowed
    }
}

private struct FixedHost: ExtensionHost {
    let response: SourceHTTPResponse
    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse { response }
}

@Suite("Extension contract and bridge")
struct ExtensionTests {
    @Test func compiledTypeScriptFixturesRunInJavaScriptCore() async throws {
        let registry = ExtensionRegistry()
        var allChapters: [[ChapterRecord]] = []
        for name in ["source-a", "source-b"] {
            let manifestURL = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
            let bundleURL = try #require(Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Fixtures"))
            let metadata = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
            let bundle = try String(contentsOf: bundleURL, encoding: .utf8)
            try await registry.registerBundled(manifest: metadata, javaScript: bundle)
            let adapter = try await registry.adapter(
                for: SourceConnection(extensionID: metadata.id, name: name), host: RejectNetwork()
            )
            let search = try await adapter.search(query: "missing", cursor: nil)
            #expect(search.items.map(\.id) == ["fixture-manga"])
            allChapters.append(try await adapter.chapters(mangaID: "fixture-manga", cursor: nil).items)
            await #expect(throws: ExtensionFailure.unsupportedMethod("getChapterPages")) {
                try await adapter.pages(mangaID: "fixture-manga", chapterID: "a:1")
            }
        }
        #expect(allChapters[0].count == 39)
        #expect(allChapters[1].count == 40)
        #expect(!allChapters[0].contains { $0.number == "21" })
        #expect(allChapters[1].contains { $0.id == "b:21" })
    }

    @Test func promiseBridgeReturnsNormalizedDataWithoutSessionSecrets() async throws {
        let runtime = JavaScriptExtensionRuntime()
        let url = try #require(URL(string: "https://example.com/catalog"))
        let response = SourceHTTPResponse(url: url, status: 200, headers: ["Set-Cookie": "private=value"], body: Data("fixture".utf8))
        let bundle = """
            var MidokuExtension = {default: {async search(input, host) {
                const response = await host.request({url: "https://example.com/catalog"});
                if (Object.keys(response.headers).some(k => k.toLowerCase() === "set-cookie")) throw Error("leaked cookie");
                return {items: [{id: response.body, title: input.query, coverURL: null}], nextCursor: null};
            }}};
            """
        let output = try await runtime.invoke(
            bundle: bundle, method: "search", input: Data(#"{"query":"Result"}"#.utf8),
            host: FixedHost(response: response)
        )
        let page = try JSONDecoder().decode(SourcePage<MangaSummary>.self, from: output)
        #expect(page.items.first?.id == "fixture")
        #expect(page.items.first?.title == "Result")
    }

    @Test func missingCapabilityImplementationAndDuplicateRegistrationAreRejected() async throws {
        let registry = ExtensionRegistry()
        await #expect(throws: ExtensionFailure.self) {
            try await registry.registerBundled(manifest: manifest(), javaScript: "var MidokuExtension = {default: {}};")
        }
        let bundle = "var MidokuExtension = {default: {async search() { return {items: [], nextCursor: null}; }}};"
        try await registry.registerBundled(manifest: manifest(), javaScript: bundle)
        await #expect(throws: ExtensionFailure.self) {
            try await registry.registerBundled(manifest: manifest(), javaScript: bundle)
        }
    }

    @Test func throwsAndMalformedResultsStayFailures() async throws {
        for result in ["throw Error('broken parser')", "return {items: [{title: 'Missing ID'}], nextCursor: null}"] {
            let registry = ExtensionRegistry()
            try await registry.registerBundled(
                manifest: manifest(),
                javaScript: "var MidokuExtension = {default: {async search() { \(result); }}};"
            )
            let adapter = try await registry.adapter(
                for: SourceConnection(extensionID: manifest().id, name: "Test"), host: RejectNetwork()
            )
            await #expect(throws: ExtensionFailure.self) { try await adapter.search(query: "test", cursor: nil) }
        }
    }

    @Test func pendingJavaScriptCallIsCancellable() async throws {
        let runtime = JavaScriptExtensionRuntime()
        let task = Task {
            try await runtime.invoke(
                bundle: "var MidokuExtension = {default: {search() { return new Promise(() => {}); }}};",
                method: "search", input: Data("{}".utf8), host: RejectNetwork()
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Suite("Source request and verification policy")
struct RequestTests {
    @Test func cookieMatchingRespectsHostPathExpiryAndSecureFlag() throws {
        let now = Date()
        let cookie = try #require(HTTPCookie(properties: [
            .name: "session", .value: "fixture", .domain: ".example.com",
            .path: "/reader", .secure: "TRUE", .expires: now.addingTimeInterval(3600)
        ]))
        for address in ["https://example.com/reader", "https://img.example.com/reader/21"] {
            #expect(SourceCookiePolicy.matches(cookie, url: try #require(URL(string: address)), now: now))
        }
        for address in [
            "https://example.com.evil.org/reader", "https://badexample.com/reader",
            "https://example.com/readers", "https://example.com/", "http://example.com/reader"
        ] {
            #expect(!SourceCookiePolicy.matches(cookie, url: try #require(URL(string: address)), now: now))
        }
        #expect(!SourceCookiePolicy.matches(
            cookie, url: try #require(URL(string: "https://example.com/reader")),
            now: now.addingTimeInterval(7200)
        ))
    }

    @Test func permissionsAreExactAndHeadersCannotOverrideSessions() throws {
        let policy = SourceRequestPolicy(domains: ["example.com"])
        for address in [
            "http://example.com", "https://example.com.evil.org", "https://example.com@evil.org",
            "https://127.0.0.1", "https://localhost", "https://example.com:8443"
        ] {
            let url = try #require(URL(string: address))
            #expect(throws: ExtensionFailure.requestNotAllowed) { try policy.validate(url) }
        }
        try policy.validate(try #require(URL(string: "https://example.com/chapter/21")))
        for name in ["Cookie", "User-Agent", "Authorization", "Host", "X-Forwarded-For"] {
            #expect(throws: ExtensionFailure.requestNotAllowed) { try policy.validate(headers: [name: "value"]) }
        }
    }

    @Test func ordinaryForbiddenPageIsNotVerification() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(!SourceHTTPResponse(url: url, status: 403, headers: [:], body: Data()).isChallenge)
        #expect(SourceHTTPResponse(url: url, status: 200, headers: ["CF-Mitigated": "challenge"], body: Data()).isChallenge)
    }

    @Test func verificationReusesSessionAndRetriesExactlyOnce() async throws {
        let url = try #require(URL(string: "https://example.com"))
        let challenge = SourceHTTPResponse(url: url, status: 403, headers: ["cf-mitigated": "challenge"], body: Data())
        let success = SourceHTTPResponse(url: url, status: 200, headers: [:], body: Data("ok".utf8))
        let transport = StubTransport([challenge, success])
        let session = StubSession()
        let resolver = StubResolver(session: session)
        let coordinator = SourceRequestCoordinator(transport: transport, sessions: session, verification: resolver, minimumSpacing: .zero)
        let result = try await coordinator.request(
            SourceHTTPRequest(url: url, headers: [:]),
            connection: SourceConnection(extensionID: manifest().id, name: "Test"),
            manifest: manifest(), interaction: .foreground
        )
        #expect(result.status == 200)
        #expect(await resolver.count == 1)
        let sent = await transport.requests
        #expect(sent.count == 2)
        #expect(sent[0].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(sent[1].value(forHTTPHeaderField: "Cookie") == "clearance=fixture")
        #expect(sent[0].value(forHTTPHeaderField: "User-Agent") == sent[1].value(forHTTPHeaderField: "User-Agent"))
    }

    @Test func repeatedChallengeDoesNotLoopAndBackgroundNeverPresentsUI() async throws {
        let url = try #require(URL(string: "https://example.com"))
        let challenge = SourceHTTPResponse(url: url, status: 503, headers: ["cf-mitigated": "challenge"], body: Data())
        for interaction in [VerificationInteraction.foreground, .background] {
            let transport = StubTransport([challenge, challenge])
            let session = StubSession()
            let resolver = StubResolver(session: session)
            let coordinator = SourceRequestCoordinator(transport: transport, sessions: session, verification: resolver, minimumSpacing: .zero)
            let expected = interaction == .foreground ? ExtensionFailure.verificationFailed : .verificationRequired
            await #expect(throws: expected) {
                try await coordinator.request(
                    SourceHTTPRequest(url: url, headers: [:]),
                    connection: SourceConnection(extensionID: manifest().id, name: "Test"),
                    manifest: manifest(), interaction: interaction
                )
            }
            #expect(await resolver.count == (interaction == .foreground ? 1 : 0))
            #expect(await transport.requests.count == (interaction == .foreground ? 2 : 1))
        }
    }

    @Test func crossDomainRedirectIsRejectedBeforeSecondRequest() async throws {
        let url = try #require(URL(string: "https://example.com"))
        let transport = StubTransport([
            SourceHTTPResponse(url: url, status: 302, headers: ["location": "https://evil.org"], body: Data())
        ])
        let coordinator = SourceRequestCoordinator(
            transport: transport, sessions: EmptySourceSession(),
            verification: UnavailableChallengeResolver(), minimumSpacing: .zero
        )
        await #expect(throws: ExtensionFailure.requestNotAllowed) {
            try await coordinator.request(
                SourceHTTPRequest(url: url, headers: [:]),
                connection: SourceConnection(extensionID: manifest().id, name: "Test"),
                manifest: manifest(), interaction: .foreground
            )
        }
        #expect(await transport.requests.count == 1)
    }
}

@Suite("Persistent connection identity")
struct ConnectionTests {
    @Test func connectionIDsSurviveReloadAndAccountsStayDistinct() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "connections.json")
        let first = SourceConnection(extensionID: "dev.midoku.tests", name: "First")
        let second = SourceConnection(extensionID: "dev.midoku.tests", name: "Second")
        try await SourceConnectionStore(fileURL: url).save([first, second])
        #expect(try await SourceConnectionStore(fileURL: url).load() == [first, second])
        let a = SourceChapterIdentity(listing: .init(connectionID: first.id, externalID: "manga"), externalID: "21")
        let b = SourceChapterIdentity(listing: .init(connectionID: second.id, externalID: "manga"), externalID: "21")
        #expect(a != b)
    }

    @Test func futureSchemaDoesNotResetOrOverwriteTheStore() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data(#"{"version":999,"connections":[]}"#.utf8)
        try original.write(to: url)
        await #expect(throws: ExtensionFailure.self) { try await SourceConnectionStore(fileURL: url).load() }
        #expect(try Data(contentsOf: url) == original)
    }
}

@Suite("Verification presentation lifecycle")
@MainActor
struct VerificationPresentationTests {
    @Test func queuedSourcesWaitForDismissalAndCancellationReleasesWaiters() async throws {
        let coordinator = ChallengeCoordinator()
        let url = try #require(URL(string: "https://example.com"))
        let policy = SourceRequestPolicy(domains: ["example.com"])
        let first = SourceChallenge(connection: .init(extensionID: manifest().id, name: "First"), url: url, policy: policy)
        let second = SourceChallenge(connection: .init(extensionID: manifest().id, name: "Second"), url: url, policy: policy)
        let firstTask = Task { try await coordinator.resolve(first) }
        while coordinator.current == nil { await Task.yield() }
        let secondTask = Task { try await coordinator.resolve(second) }
        await Task.yield()
        coordinator.retry(id: first.id)
        try await firstTask.value
        #expect(coordinator.current == nil)
        coordinator.presentationDidDismiss()
        while coordinator.current == nil { await Task.yield() }
        #expect(coordinator.current?.id == second.id)
        secondTask.cancel()
        await #expect(throws: CancellationError.self) { try await secondTask.value }
        #expect(coordinator.current == nil)
        coordinator.presentationDidDismiss()
        #expect(coordinator.current == nil)
    }
}


private actor StubBrowser: SourceBrowserRendering {
    var calls = 0
    let alwaysChallenge: Bool
    init(alwaysChallenge: Bool = false) { self.alwaysChallenge = alwaysChallenge }
    func render(_ response: SourceHTTPResponse, script: String, connection: SourceConnection, policy: SourceRequestPolicy) async throws -> SourceHTTPResponse {
        calls += 1
        if calls == 1 || alwaysChallenge { throw ExtensionFailure.verificationRequired }
        return SourceHTTPResponse(url: response.url, status: 200, headers: [:], body: Data("{}".utf8))
    }
}
@Suite("Browser extraction verification")
struct BrowserExtractionTests {
    @Test func foregroundRetriesOnceAndBackgroundNeverPrompts() async throws {
        let url = try #require(URL(string: "https://example.com/browse"))
        let html = SourceHTTPResponse(url: url, status: 200, headers: [:], body: Data("<html/>".utf8))
        let permitted = ExtensionManifest(id: "dev.midoku.tests", name: "Test", version: "1.0.0", contractVersion: 2,
            domains: ["example.com"], capabilities: [.search], browserRendering: true)
        for interaction in [VerificationInteraction.foreground, .background] {
            let session = StubSession(), browser = StubBrowser(), transport = StubTransport([html, html])
            let resolver = StubResolver(session: session)
            let coordinator = SourceRequestCoordinator(transport: transport, sessions: session, verification: resolver, minimumSpacing: .zero, browser: browser)
            let request = SourceHTTPRequest(url: url, headers: [:], browserScript: "window.__midokuResult='{}'")
            let connection = SourceConnection(extensionID: permitted.id, name: "Test")
            if interaction == .foreground {
                #expect(try await coordinator.request(request, connection: connection, manifest: permitted, interaction: interaction).status == 200)
                #expect(await resolver.count == 1)
                #expect(await browser.calls == 2)
            } else {
                await #expect(throws: ExtensionFailure.verificationRequired) {
                    try await coordinator.request(request, connection: connection, manifest: permitted, interaction: interaction)
                }
                #expect(await resolver.count == 0)
                #expect(await browser.calls == 1)
            }
        }
    }
    @Test func browserRequiresExplicitManifestPermission() async throws {
        let url = try #require(URL(string: "https://example.com"))
        let transport = StubTransport([])
        let coordinator = SourceRequestCoordinator(transport: transport, sessions: EmptySourceSession(), verification: UnavailableChallengeResolver(), browser: StubBrowser())
        await #expect(throws: ExtensionFailure.requestNotAllowed) {
            try await coordinator.request(SourceHTTPRequest(url: url, headers: [:], browserScript: "window.__midokuResult='{}'"),
                connection: SourceConnection(extensionID: manifest().id, name: "Test"), manifest: manifest(), interaction: .foreground)
        }
        #expect(await transport.requests.isEmpty)
    }
}
