import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Verification recovery")
@MainActor
struct VerificationRecoveryTests {
    @Test func liveContainerModesUseTemporaryProfilesWithoutChangingNativeInstalls() {
        #expect(SourceBrowserProfileMode.selected(environment: [:]) == .persistent)
        #expect(SourceBrowserProfileMode.selected(environment: ["LC_HOME_PATH": ""]) == .persistent)
        #expect(SourceBrowserProfileMode.selected(environment: ["LC_HOME_PATH": "/fixture/host"]) == .temporary)
        #expect(SourceBrowserProfileMode.selected(environment: ["LP_HOME_PATH": "/fixture/process"]) == .temporary)
    }

    @Test(arguments: [false, true])
    func explicitRetryWhileBrowserStillHasChallengeIsBounded(stillChallenged: Bool) async throws {
        let url = try #require(URL(string: "https://example.com/catalog"))
        let manifest = ExtensionManifest(id: "dev.midoku.recovery", name: "Recovery", version: "1.0.0",
            contractVersion: 1, domains: ["example.com"], capabilities: [.search])
        let connection = SourceConnection(extensionID: manifest.id, name: "Recovery")
        let challenge = SourceHTTPResponse(url: url, status: 403, headers: ["cf-mitigated": "challenge"], body: Data())
        let success = SourceHTTPResponse(url: url, status: 200, headers: [:], body: Data("ok".utf8))
        let transport = RecoveryTransport(responses: [challenge, stillChallenged ? challenge : success])
        let session = RecoverySession()
        let presentation = ChallengeCoordinator()
        let requests = SourceRequestCoordinator(transport: transport, sessions: session,
            verification: presentation, minimumSpacing: .zero)
        let task = Task {
            try await requests.request(SourceHTTPRequest(url: url, headers: [:]), connection: connection,
                manifest: manifest, interaction: .foreground)
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while presentation.current == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = try #require(presentation.current)
        await session.receivedClearance()
        // Same action as the recovery button. It requests access without pretending
        // that the browser's challenge page has completed successfully.
        presentation.retry(id: pending.id)
        if stillChallenged {
            await #expect(throws: ExtensionFailure.verificationFailed) { try await task.value }
        } else {
            let response = try await task.value
            #expect(response.body == Data("ok".utf8))
        }
        presentation.presentationDidDismiss()
        #expect(presentation.current == nil)
        let sent = await transport.requests
        #expect(sent.count == 2)
        #expect(sent[0].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(sent[1].value(forHTTPHeaderField: "Cookie") == "cf_clearance=fixture")
        #expect(sent[0].value(forHTTPHeaderField: "User-Agent") == sent[1].value(forHTTPHeaderField: "User-Agent"))
    }
}

private actor RecoveryTransport: SourceHTTPTransport {
    var responses: [SourceHTTPResponse]
    var requests: [URLRequest] = []
    init(responses: [SourceHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest, maximumBytes: Int) throws -> SourceHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ExtensionFailure.invalidResponse("Unexpected retry.") }
        return responses.removeFirst()
    }
}

private actor RecoverySession: SourceSessionProviding {
    var cleared = false
    func receivedClearance() { cleared = true }
    func headers(for url: URL, connectionID: UUID) -> [String: String] {
        var headers = ["User-Agent": "Fixture WebKit"]
        if cleared { headers["Cookie"] = "cf_clearance=fixture" }
        return headers
    }
    func receive(_ response: SourceHTTPResponse, connectionID: UUID) {}
}
