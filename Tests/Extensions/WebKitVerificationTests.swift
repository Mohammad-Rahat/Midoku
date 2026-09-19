#if canImport(AppKit)
import AppKit
import WebKit
import Testing
@testable import MidokuExtensions

/// Exercise actual WKNavigationAction URLs, not only Foundation URL(string:) fixtures.
@Suite("Native WebKit verification frames", .serialized)
@MainActor
struct WebKitVerificationTests {
    @Test func opaqueFramesSuppliedByWebKitLoadAndRunScripts() async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let recorder = FrameRecorder()
        config.userContentController.add(recorder, name: "fixture")
        let browser = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let window = NSWindow(contentRect: browser.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = browser
        window.orderFrontRegardless()
        browser.navigationDelegate = recorder
        defer {
            browser.stopLoading()
            browser.navigationDelegate = nil
            config.userContentController.removeScriptMessageHandler(forName: "fixture")
            window.close()
        }
        browser.loadHTMLString(Self.html, baseURL: try #require(URL(string: "https://example.com/")))
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        let expected: Set<String> = ["srcdoc", "nested", "blob"]
        while ContinuousClock.now < deadline {
            if recorder.completed.isSuperset(of: expected), recorder.dataDenied { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(recorder.completed.isSuperset(of: expected))
        #expect(recorder.localDocuments.contains("about:blank"))
        #expect(recorder.localDocuments.contains("about:srcdoc"))
        #expect(recorder.deniedLocalDocuments.isEmpty)
        #expect(recorder.dataDenied)
        #expect(!recorder.completed.contains("data"))
    }

    private static let html = #"""
    <!doctype html><meta charset="utf-8"><title>Verification frame fixture</title>
    <script>
    window.addEventListener('message', event => {
        if (['srcdoc','nested','blob','data'].includes(event.data)) {
            window.webkit.messageHandlers.fixture.postMessage(event.data);
        }
    });
    function content(name) { return '<script>top.postMessage("' + name + '", "*")<\/script>'; }
    function frame(src, srcdoc) {
        const node = document.createElement('iframe');
        if (srcdoc !== undefined) node.srcdoc = srcdoc; else node.src = src;
        document.body.appendChild(node);
    }
    window.onload = () => {
        frame('about:blank');
        frame(null, content('srcdoc'));
        frame(null, '<iframe sandbox="allow-scripts" srcdoc="&lt;script&gt;top.postMessage(\'nested\',\'*\')&lt;/script&gt;"></iframe>');
        frame(URL.createObjectURL(new Blob([content('blob')], {type: 'text/html'})));
        frame('data:text/html,' + encodeURIComponent(content('data')));
    };
    </script><body>Local test only</body>
    """#
}

@MainActor
private final class FrameRecorder: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let policy = SourceRequestPolicy(domains: ["example.com"])
    var bootstrap = true
    var completed = Set<String>()
    var localDocuments = Set<String>()
    var deniedLocalDocuments = Set<String>()
    var dataDenied = false

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if bootstrap, action.targetFrame?.isMainFrame == true {
            bootstrap = false
            return .allow
        }
        let allow = SourceVerificationPolicy.allowsNavigation(
            to: url, isMainFrame: action.targetFrame?.isMainFrame ?? true, policy: policy
        )
        if let kind = SourceVerificationPolicy.localDocument(url) {
            localDocuments.insert(kind)
            if !allow { deniedLocalDocuments.insert(kind) }
        }
        if url.scheme == "data", !allow { dataDenied = true }
        return allow ? .allow : .cancel
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let name = message.body as? String { completed.insert(name) }
    }
}
#endif
