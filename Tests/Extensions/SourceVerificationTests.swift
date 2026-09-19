import Foundation
import JavaScriptCore
import Testing
@testable import MidokuExtensions

@Suite("Browser verification lifecycle")
struct SourceVerificationTests {
    private let policy = SourceRequestPolicy(domains: ["example.com"])

    @Test func turnstileLocalFramesAndCloudflareFramesAreAllowedOnlyInsideTheSource() throws {
        for address in [
            "about:blank", "about:srcdoc", "about:blank#frame",
            "https://challenges.cloudflare.com/turnstile/v0/widget",
            "blob:https://challenges.cloudflare.com/fixture",
            "blob:https://example.com/fixture"
        ] {
            let url = try #require(URL(string: address))
            #expect(SourceVerificationPolicy.allowsNavigation(to: url, isMainFrame: false, policy: policy))
            #expect(!SourceVerificationPolicy.allowsNavigation(to: url, isMainFrame: true, policy: policy))
            #expect(throws: ExtensionFailure.requestNotAllowed) { try policy.validate(url) }
        }
        let source = try #require(URL(string: "https://example.com/cdn-cgi/challenge-platform/"))
        #expect(SourceVerificationPolicy.allowsNavigation(to: source, isMainFrame: true, policy: policy))
        #expect(SourceVerificationPolicy.allowsNavigation(to: source, isMainFrame: false, policy: policy))
    }

    @Test func frameExceptionsDoNotPermitLookalikesFilesPrivateHostsOrExternalWindows() throws {
        for address in [
            "https://challenges.cloudflare.com.evil.org/frame", "https://evil.org/",
            "http://challenges.cloudflare.com/", "https://challenges.cloudflare.com:8443/",
            "https://user:password@challenges.cloudflare.com/", "about:config",
            "about:srcdoc?external=1", "blob:https://evil.org/fixture",
            "blob:http://example.com/fixture", "blob:null/fixture", "data:text/html,fixture",
            "file:///etc/hosts", "https://127.0.0.1/", "javascript:alert(1)"
        ] {
            let url = try #require(URL(string: address))
            for isMainFrame in [true, false] {
                #expect(!SourceVerificationPolicy.allowsNavigation(to: url, isMainFrame: isMainFrame, policy: policy))
            }
        }
    }

    @Test func browserRequestPreservesIdentityButLetsWebKitOwnCookies() throws {
        let url = try #require(URL(string: "https://example.com/catalog"))
        let challenge = SourceChallenge(
            connection: SourceConnection(extensionID: "dev.midoku.tests", name: "Test"),
            url: url, policy: policy, headers: [
                "cOoKiE": "cf_clearance=rejected; login=old", "User-Agent": "Fixture iPhone WebKit",
                "Accept": "text/html", "Accept-Language": "en", "Referer": "https://example.com/",
                "Host": "untrusted.org", "Authorization": "secret", "Origin": "https://untrusted.org"
            ]
        )
        let request = try SourceVerificationPolicy.request(for: challenge)
        #expect(request.url == url)
        #expect(request.httpMethod == "GET")
        #expect(request.httpShouldHandleCookies)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Host") == nil)
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Fixture iPhone WebKit")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://example.com/")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/html")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")
    }

    @Test func invalidBrowserRequestCannotSmuggleHeadersOrNavigateElsewhere() throws {
        let connection = SourceConnection(extensionID: "dev.midoku.tests", name: "Test")
        let url = try #require(URL(string: "https://example.com/"))
        for headers in [
            ["User-Agent": "browser\r\nCookie: value"], ["User-Agent": "browser\rCookie: value"],
            ["User-Agent": "browser\nCookie: value"], ["Accept": "text/html\r\nCookie: value"],
            ["Accept-Language": "en\nCookie: value"], ["Referer": "https://evil.org/"]
        ] {
            #expect(throws: ExtensionFailure.requestNotAllowed) {
                try SourceVerificationPolicy.request(for: SourceChallenge(
                    connection: connection, url: url, policy: policy, headers: headers
                ))
            }
        }
        let external = try #require(URL(string: "https://evil.org/"))
        #expect(throws: ExtensionFailure.requestNotAllowed) {
            try SourceVerificationPolicy.request(for: SourceChallenge(connection: connection, url: external, policy: policy))
        }
    }

    @Test func completionRequiresFinishedSuccessfulPageAndFreshClearance() {
        var state = SourceVerificationProgress()
        state.navigationStarted()
        let unfinished = state.complete(revision: state.revision, hasFreshClearance: true, pageState: "ready")
        #expect(!unfinished)
        state.received(statusCode: 403)
        state.navigationFinished()
        let forbidden = state.complete(revision: state.revision, hasFreshClearance: true, pageState: "ready")
        #expect(!forbidden)
        state.received(statusCode: 200)
        for page in [nil, "loading", "challenge", "unavailable"] as [String?] {
            let incompletePage = state.complete(revision: state.revision, hasFreshClearance: true, pageState: page)
            #expect(!incompletePage)
        }
        let staleClearance = state.complete(revision: state.revision, hasFreshClearance: false, pageState: "ready")
        #expect(!staleClearance)
        let completed = state.complete(revision: state.revision, hasFreshClearance: true, pageState: "ready")
        #expect(completed)
        let duplicate = state.complete(revision: state.revision, hasFreshClearance: true, pageState: "ready")
        #expect(!duplicate)
    }

    @Test func delayedCallbacksCannotFinishNewNavigationCancelledOrTimedOutAttempt() {
        var state = SourceVerificationProgress()
        state.navigationStarted()
        state.received(statusCode: 200)
        state.navigationFinished()
        let oldRevision = state.revision
        state.navigationStarted()
        state.received(statusCode: 200)
        state.navigationFinished()
        let obsoleteNavigation = state.complete(revision: oldRevision, hasFreshClearance: true, pageState: "ready")
        #expect(!obsoleteNavigation)
        let currentRevision = state.revision
        state.stop()
        let stopped = state.complete(revision: currentRevision, hasFreshClearance: true, pageState: "ready")
        #expect(!stopped)
        state.navigationFinished()
        let lateCallback = state.complete(revision: state.revision, hasFreshClearance: true, pageState: "ready")
        #expect(!lateCallback)
    }

    @Test func cookieComparisonRejectsUnchangedExpiredWrongPathAndForeignDomain() throws {
        let url = try #require(URL(string: "https://example.com/catalog"))
        func cookie(_ value: String, domain: String = ".example.com", path: String = "/", expiry: Date = .distantFuture) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [
                .name: "cf_clearance", .value: value, .domain: domain,
                .path: path, .secure: "TRUE", .expires: expiry
            ]))
        }
        let previous: Set<String> = ["old-root", "old-path"]
        let ignored = try [
            cookie("old-root"), cookie("old-path", path: "/catalog"), cookie(""),
            cookie("new", domain: ".other.org"), cookie("new", path: "/account"),
            cookie("new", expiry: .distantPast)
        ]
        #expect(!SourceCookiePolicy.hasFreshCloudflareClearance(in: ignored, for: url, previousValues: previous))
        #expect(SourceCookiePolicy.hasFreshCloudflareClearance(in: try ignored + [cookie("new")], for: url, previousValues: previous))
        #expect(!SourceCookiePolicy.hasFreshCloudflareClearance(in: [], for: url, previousValues: []))
    }

    @Test func pageInspectionDoesNotTreatLoadingChallengeOrScriptFailureAsReady() throws {
        let context = try #require(JSContext())
        for (readyState, title, hasWidget, expected) in [
            ("loading", "", false, "loading"), ("complete", "Just a moment...", false, "challenge"),
            ("complete", "Website", true, "challenge"), ("complete", "Website", false, "ready")
        ] {
            context.evaluateScript("var document = { readyState: '\(readyState)', title: '\(title)', querySelector: () => (\(hasWidget ? "{}" : "null")) };")
            #expect(context.evaluateScript(SourceVerificationPolicy.pageStateScript)?.toString() == expected)
            #expect(context.exception == nil)
        }
        context.evaluateScript("document.querySelector = () => { throw new Error('fixture'); };")
        let result = context.evaluateScript(SourceVerificationPolicy.pageStateScript)
        #expect(result?.toString() != "ready")
        #expect(context.exception != nil)
    }
}
