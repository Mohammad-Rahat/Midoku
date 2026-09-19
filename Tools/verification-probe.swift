// Read-only macOS WebKit probe. Logs origins/frame roles, never paths, tokens or cookies.
import AppKit
import WebKit
import Foundation

@MainActor
final class VerificationProbe: NSObject, WKNavigationDelegate {
    let policy: SourceRequestPolicy
    let enforcePolicy: Bool
    var trace: [[String: Any]] = []
    var blocked = 0
    var lastStatus: Int?
    var allowFixtureBootstrap = false

    init(host: String, enforcePolicy: Bool) {
        policy = SourceRequestPolicy(domains: [host])
        self.enforcePolicy = enforcePolicy
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if allowFixtureBootstrap, action.targetFrame?.isMainFrame == true {
            allowFixtureBootstrap = false
            return .allow
        }
        let main = action.targetFrame?.isMainFrame ?? true
        let allowed = SourceVerificationPolicy.allowsNavigation(to: url, isMainFrame: main, policy: policy)
        let aboutKind = url.scheme == "about" ?
            (["blank", "srcdoc"].contains(url.path) ? url.path : "other") : "none"
        if trace.count < 40 {
            trace.append([
                "scheme": url.scheme ?? "none", "host": url.host ?? "none",
                "aboutKind": aboutKind, "hasQuery": url.query != nil,
                "localDocument": SourceVerificationPolicy.localDocument(url) ?? "none",
                "target": action.targetFrame.map { $0.isMainFrame ? "main" : "subframe" } ?? "new-window",
                "sourceMain": action.sourceFrame.isMainFrame,
                "sourceHost": action.sourceFrame.securityOrigin.host,
                "allowedByCurrentPolicy": allowed
            ])
        }
        if !allowed { blocked += 1 }
        if enforcePolicy { return allowed ? .allow : .cancel }
        // Like a normal browser, leave embedded frames alone. Keep top-level
        // browsing in the explicitly selected source even in the comparison run.
        return main ? (allowed ? .allow : .cancel) : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse { lastStatus = http.statusCode }
        return .allow
    }
}

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
window.orderFrontRegardless()

func report(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
}

let fixture = #"""
<!doctype html><meta charset="utf-8"><title>Frame fixture</title>
<script>
window.completedFrames = [];
window.addEventListener('message', event => {
    if (typeof event.data === 'string' && event.data.startsWith('fixture:')) {
        completedFrames.push(event.data.slice(8));
    }
});
function add(kind, url, content) {
    const frame = document.createElement('iframe');
    frame.name = kind;
    if (content !== undefined) frame.srcdoc = content;
    else frame.src = url;
    frame.onload = () => {
        if (kind === 'blank' || kind === 'blank-query') completedFrames.push(kind);
    };
    document.body.appendChild(frame);
}
function contents(kind) { return '<script>parent.postMessage("fixture:' + kind + '", "*")<\/script>'; }
window.onload = () => {
    add('blank', 'about:blank');
    add('blank-query', 'about:blank?fixture=1');
    add('srcdoc', null, contents('srcdoc'));
    add('sandboxed-srcdoc', null, '<iframe sandbox="allow-scripts" srcdoc="&lt;script&gt;top.postMessage(\'fixture:sandboxed-srcdoc\',\'*\')&lt;/script&gt;"></iframe>');
    add('data', 'data:text/html,' + encodeURIComponent(contents('data')));
    add('blob', URL.createObjectURL(new Blob([contents('blob')], {type: 'text/html'})));
};
</script><body>Frame navigation probe</body>
"""#

Task { @MainActor in
    for enforce in [true, false] {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: config)
        let delegate = VerificationProbe(host: "example.com", enforcePolicy: enforce)
        delegate.allowFixtureBootstrap = true
        web.navigationDelegate = delegate
        window.contentView = web
        web.loadHTMLString(fixture, baseURL: URL(string: "https://example.com/"))
        try? await Task.sleep(for: .seconds(5))
        let frames = (try? await web.evaluateJavaScript("window.completedFrames || []")) as? [String] ?? []
        report(["phase": "fixture", "enforced": enforce, "completed": frames.sorted(), "blockedByPolicy": delegate.blocked, "trace": delegate.trace])
        if enforce, !Set(frames).isSuperset(of: ["srcdoc", "sandboxed-srcdoc", "blob"]) {
            report(["phase": "fixture", "error": "Required embedded documents failed to execute"])
            exit(1)
        }
        web.stopLoading()
        web.navigationDelegate = nil
    }

    // Inspect the homepage flow, then one adapter search through the production host.
    guard let url = URL(string: "https://novelcrow.com/") else { exit(1) }
    for enforce in [true, false] {
        let sessions = BrowserSessionStore()
        let connection = SourceConnection(extensionID: "dev.midoku.novelcrow", name: "NovelCrow probe")
        do { _ = try await sessions.headers(for: url, connectionID: connection.id) }
        catch { report(["phase": "live-macos", "error": "Could not initialize browser identity"]); exit(1) }
        let web = sessions.makeWebView(for: connection.id)
        web.frame = window.contentView?.bounds ?? .zero
        let delegate = VerificationProbe(host: "novelcrow.com", enforcePolicy: enforce)
        web.navigationDelegate = delegate
        window.contentView = web
        web.load(URLRequest(url: url))
        try? await Task.sleep(for: .seconds(20))
        let cookies = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
        let hasClearance = cookies.contains { $0.name == "cf_clearance" }
        let rawState = (try? await web.evaluateJavaScript(SourceVerificationPolicy.pageStateScript)) as? String
        let state = rawState.flatMap { ["loading", "challenge", "ready"].contains($0) ? $0 : nil } ?? "unavailable"
        report(["phase": "live-macos", "enforced": enforce, "status": delegate.lastStatus ?? 0, "page": state,
                "hasClearance": hasClearance, "blockedByPolicy": delegate.blocked, "trace": delegate.trace])
        if enforce {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                for (key, value) in try await sessions.headers(for: url, connectionID: connection.id) {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                let transport = URLSessionSourceTransport()
                let response = try await transport.send(request, maximumBytes: 8 * 1024 * 1024)
                report(["phase": "native-retry", "status": response.status, "challenge": response.isChallenge])
                let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf:
                    URL(fileURLWithPath: "Extensions/sources/dev.midoku.novelcrow/manifest.json")))
                let bundle = try String(contentsOf: URL(fileURLWithPath: "Extensions/dist/dev.midoku.novelcrow/bundle.js"), encoding: .utf8)
                let coordinator = SourceRequestCoordinator(transport: transport, sessions: sessions,
                    verification: UnavailableChallengeResolver(), browser: SourceBrowserRenderer(sessions: sessions))
                let host = NetworkExtensionHost(coordinator: coordinator, connection: connection, manifest: manifest, interaction: .background)
                let runtime = JavaScriptExtensionRuntime()
                try await runtime.validate(bundle: bundle, manifest: manifest)
                let output = try await runtime.invoke(bundle: bundle, method: "search",
                    input: Data(#"{"query":"One Piece","cursor":null,"filters":{}}"#.utf8), host: host)
                let page = try JSONDecoder().decode(SourcePage<MangaSummary>.self, from: output)
                report(["phase": "live-extension-search", "succeeded": true, "itemCount": page.items.count])
            } catch let error as ExtensionFailure {
                // Host errors have fixed redacted descriptions. Do not log arbitrary errors or URLs.
                report(["phase": "live-extension-search", "succeeded": false, "error": error.localizedDescription])
            } catch {
                report(["phase": "live-extension-search", "succeeded": false, "error": "Probe could not complete"])
            }
        }
        web.stopLoading()
        web.navigationDelegate = nil
        await sessions.clearSession(for: connection.id)
    }
    exit(0)
}
app.run()
