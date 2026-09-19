import Foundation
import WebKit

/// WebKit persists each profile separately. No cookies enter UserDefaults or adapter JS.
@MainActor
final class BrowserSessionStore: SourceSessionProviding {
    private var profiles: [UUID: WKWebsiteDataStore] = [:]
    private var userAgents: [UUID: String] = [:]

    func dataStore(for connectionID: UUID) -> WKWebsiteDataStore {
        if let profile = profiles[connectionID] { return profile }
        let profile = WKWebsiteDataStore(forIdentifier: connectionID)
        profiles[connectionID] = profile
        return profile
    }

    func makeWebView(for connectionID: UUID) -> WKWebView {
        makeWebView(for: connectionID, dataStore: dataStore(for: connectionID))
    }

    /// Cloudflare's challenge runtime is tested against WebKit's default browser store.
    /// Solved cookies are copied back to the connection-specific profile afterward.
    func makeVerificationWebView(for connectionID: UUID) -> WKWebView {
        makeWebView(for: connectionID, dataStore: .default())
    }

    private func makeWebView(for connectionID: UUID, dataStore: WKWebsiteDataStore) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        if let userAgent = userAgents[connectionID],
           userAgent.contains("iPhone") || userAgent.contains("iPad") {
            // Cloudflare binds clearance to browser characteristics. Keep WebKit's
            // rendering mode aligned with the mobile UA used by the native request.
            configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        if let userAgent = userAgents[connectionID] {
            view.customUserAgent = userAgent
        }
        return view
    }

    func prepareVerification(for url: URL, connectionID: UUID) async {
        let sourceStore = dataStore(for: connectionID).httpCookieStore
        let verificationStore = WKWebsiteDataStore.default().httpCookieStore
        let sourceCookies = await sourceStore.allCookies()
        let verificationCookies = await verificationStore.allCookies()

        // The request was challenged, so any existing clearance is stale. Mihon
        // removes it before opening WebView; doing the same prevents challenge loops.
        for cookie in sourceCookies where cookie.name == "cf_clearance" &&
            SourceCookiePolicy.domainMatches(cookie, host: url.host ?? "") {
            await sourceStore.deleteCookie(cookie)
        }
        for cookie in verificationCookies where
            SourceCookiePolicy.domainMatches(cookie, host: url.host ?? "") {
            await verificationStore.deleteCookie(cookie)
        }
        for cookie in sourceCookies where cookie.name != "cf_clearance" &&
            SourceCookiePolicy.matches(cookie, url: url) {
            await verificationStore.setCookie(cookie)
        }
    }

    func importVerificationCookies(for url: URL, connectionID: UUID) async {
        let sourceStore = dataStore(for: connectionID).httpCookieStore
        let verificationStore = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await verificationStore.allCookies()
        let cookies = allCookies.filter {
            SourceCookiePolicy.matches($0, url: url)
        }
        for cookie in cookies {
            await sourceStore.setCookie(cookie)
        }
    }

    func clearSession(for connectionID: UUID) async {
        let store = dataStore(for: connectionID)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        userAgents.removeValue(forKey: connectionID)
    }

    @MainActor
    func headers(for url: URL, connectionID: UUID) async throws -> [String: String] {
        if userAgents[connectionID] == nil {
            // Read the installed WebKit UA instead of fabricating a browser/version string.
            let webView = makeWebView(for: connectionID)
            let value = try await webView.evaluateJavaScript("navigator.userAgent")
            guard let userAgent = value as? String, !userAgent.isEmpty else {
                throw ExtensionFailure.verificationFailed
            }
            userAgents[connectionID] = userAgent
        }
        let allCookies = await dataStore(for: connectionID).httpCookieStore.allCookies()
        let cookies = allCookies.filter { SourceCookiePolicy.matches($0, url: url) }
            .sorted { $0.path.count > $1.path.count }
        var headers = HTTPCookie.requestHeaderFields(with: cookies)
        headers["User-Agent"] = userAgents[connectionID]
        return headers
    }

    @MainActor
    func receive(_ response: SourceHTTPResponse, connectionID: UUID) async throws {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.headers, for: response.url)
        let store = dataStore(for: connectionID).httpCookieStore
        for cookie in cookies {
            // Reject cookies that cannot belong to this response's host.
            guard SourceCookiePolicy.domainMatches(cookie, host: response.url.host ?? "") else { continue }
            await store.setCookie(cookie)
        }
    }

}
