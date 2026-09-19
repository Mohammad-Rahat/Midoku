import Foundation
import WebKit

/// Browser execution is serialized by SourceRequestCoordinator and shares only its connection's profile.
@MainActor
final class SourceBrowserRenderer: SourceBrowserRendering {
    let sessions: BrowserSessionStore
    init(sessions: BrowserSessionStore) { self.sessions = sessions }

    func render(_ response: SourceHTTPResponse, script: String, connection: SourceConnection, policy: SourceRequestPolicy) async throws -> SourceHTTPResponse {
        try Task.checkCancellation()
        let view = sessions.makeWebView(for: connection.id)
        view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let navigation = BrowserNavigation(policy: policy)
        view.navigationDelegate = navigation
        let blocker = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "midoku-extract-" + connection.id.uuidString,
            encodedContentRuleList: SourceBrowserRules.encoded(domains: policy.domains))
        if let blocker { view.configuration.userContentController.add(blocker) }
        view.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        defer {
            view.stopLoading(); view.navigationDelegate = nil
            view.configuration.userContentController.removeAllUserScripts()
        }
        // Keep module locators available to the reviewed extractor without starting the
        // website UI, its unsolicited catalogue queries, or advertisement initialization.
        let html = String(decoding: response.body, as: UTF8.self)
            .replacingOccurrences(of: "type=\"module\"", with: "type=\"application/x-midoku-module\"")
            .replacingOccurrences(of: "type='module'", with: "type='application/x-midoku-module'")
        view.loadHTMLString(html, baseURL: response.url)
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let failure = navigation.failure { throw failure }
            let result = try? await view.evaluateJavaScript("window.__midokuResult || null")
            if let string = result as? String {
                guard string.utf8.count <= 4 * 1024 * 1024 else { throw ExtensionFailure.responseTooLarge }
                let data = Data(string.utf8)
                if let error = try JSONSerialization.jsonObject(with: data) as? [String: Any], error["midokuError"] != nil {
                    if error["midokuError"] as? String == "verification" { throw ExtensionFailure.verificationRequired }
                    throw ExtensionFailure.invalidResponse("Website extraction failed.")
                }
                return SourceHTTPResponse(url: response.url, status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
            let challenge = try? await view.evaluateJavaScript("!!(document.querySelector('#challenge-running, #challenge-stage, form#challenge-form') || document.title === 'Just a moment...')")
            if challenge as? Bool == true { throw ExtensionFailure.verificationRequired }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ExtensionFailure.timedOut
    }
}

@MainActor
private final class BrowserNavigation: NSObject, WKNavigationDelegate {
    let policy: SourceRequestPolicy
    var failure: ExtensionFailure?
    init(policy: SourceRequestPolicy) { self.policy = policy }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, navigationAction.targetFrame != nil else { return .cancel }
        if url.absoluteString == "about:blank" { return .allow }
        return SourceVerificationPolicy.allowsNavigation(
            to: url, isMainFrame: navigationAction.targetFrame?.isMainFrame != false, policy: policy
        ) ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { failure = .invalidResponse("Website could not load.") }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failure = .runtimeFailure }
}
