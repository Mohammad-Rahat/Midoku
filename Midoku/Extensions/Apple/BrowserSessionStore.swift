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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: connectionID)
        let view = WKWebView(frame: .zero, configuration: configuration)
        if let userAgent = userAgents[connectionID] {
            view.customUserAgent = userAgent
        }
        return view
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

