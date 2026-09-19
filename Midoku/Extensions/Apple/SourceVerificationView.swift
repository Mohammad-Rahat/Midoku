import SwiftUI
import WebKit

struct SourceVerificationView: View {
    let challenge: SourceChallenge
    let sessions: BrowserSessionStore
    let coordinator: ChallengeCoordinator
    @State private var attemptID = UUID()
    @State private var status = "Checking website…"
    @State private var details = "Preparing WebKit verification (revision 5)."
    @State private var loadError: String?
    @State private var canTryRequest = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(challenge.url.host ?? challenge.connection.name)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                    if sessions.profileMode == .temporary {
                        Text("This browser session lasts until you close the app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let loadError {
                        Text(loadError).font(.footnote).foregroundStyle(.red)
                    }
                    DisclosureGroup("Connection details") {
                        Text(details).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                Divider()
                if loadError != nil {
                    // Removing the representable releases the looping document,
                    // including its timers. stopLoading alone does not stop scripts.
                    ContentUnavailableView {
                        Label("Verification paused", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Start another verification attempt when you’re ready.")
                    } actions: {
                        Button("Reload verification") { reload() }
                    }
                } else {
                    VerificationBrowser(
                        challenge: challenge,
                        sessions: sessions,
                        onVerified: { coordinator.retry(id: challenge.id) },
                        onCanTryRequest: { canTryRequest = $0 },
                        onStatus: { status = $0 },
                        onDetails: { details = $0 },
                        onError: { loadError = $0 }
                    )
                    .id(attemptID)
                }
            }
            .navigationTitle("Verify source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { coordinator.cancel(id: challenge.id) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("Try request") { coordinator.retry(id: challenge.id) }
                            .disabled(!canTryRequest)
                        Button("Reload verification") { reload() }
                    } label: {
                        Text(canTryRequest ? "Try request" : "Reload")
                    } primaryAction: {
                        if canTryRequest { coordinator.retry(id: challenge.id) }
                        else { reload() }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func reload() {
        loadError = nil
        canTryRequest = false
        status = "Checking website…"
        details = "Preparing WebKit verification (revision 5)."
        attemptID = UUID()
    }
}

private struct VerificationBrowser: UIViewControllerRepresentable {
    let challenge: SourceChallenge
    let sessions: BrowserSessionStore
    let onVerified: () -> Void
    let onCanTryRequest: (Bool) -> Void
    let onStatus: (String) -> Void
    let onDetails: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> VerificationBrowserController {
        VerificationBrowserController(
            challenge: challenge, sessions: sessions, onVerified: onVerified, onCanTryRequest: onCanTryRequest,
            onStatus: onStatus, onDetails: onDetails, onError: onError
        )
    }

    func updateUIViewController(_ controller: VerificationBrowserController, context: Context) {}

    static func dismantleUIViewController(_ controller: VerificationBrowserController, coordinator: ()) {
        controller.stop()
    }
}

/// Aidoku-style lifecycle: attach first, try the real URL in a small browser,
/// then expose that SAME browser for interaction. The profile remains connection-
/// scoped; no cookies or website storage are copied through a global browser jar.
@MainActor
private final class VerificationBrowserController: UIViewController, WKNavigationDelegate {
    private let challenge: SourceChallenge
    private let sessions: BrowserSessionStore
    private let onVerified: () -> Void
    private let onCanTryRequest: (Bool) -> Void
    private let onStatus: (String) -> Void
    private let onDetails: (String) -> Void
    private let onError: (String) -> Void
    private var webView: WKWebView?
    private var hiddenConstraints: [NSLayoutConstraint] = []
    private var monitorTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var progress = SourceVerificationProgress()
    private var previousClearanceValues = Set<String>()
    private var didStart = false
    private var isVisible = false
    private var firstFinish: ContinuousClock.Instant?
    private var localFrames = 0
    private var cloudflareFrames = 0
    private var blockedNavigations = 0
    private var blockedLabels: [String] = []
    private var clearanceState = "not checked"
    private var pageState = "loading"

    init(
        challenge: SourceChallenge, sessions: BrowserSessionStore,
        onVerified: @escaping () -> Void, onCanTryRequest: @escaping (Bool) -> Void, onStatus: @escaping (String) -> Void,
        onDetails: @escaping (String) -> Void, onError: @escaping (String) -> Void
    ) {
        self.challenge = challenge
        self.sessions = sessions
        self.onVerified = onVerified
        self.onCanTryRequest = onCanTryRequest
        self.onStatus = onStatus
        self.onDetails = onDetails
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let browser = sessions.makeWebView(for: challenge.connection.id)
        browser.navigationDelegate = self
        browser.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browser)
        hiddenConstraints = [
            browser.widthAnchor.constraint(equalToConstant: 0),
            browser.heightAnchor.constraint(equalToConstant: 0),
            browser.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            browser.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ]
        NSLayoutConstraint.activate(hiddenConstraints)
        webView = browser
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Do not load from makeUIView, before UIKit has attached the browser.
        guard !didStart, let webView, webView.window != nil else { return }
        didStart = true
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            self?.fail("Verification timed out. Tap Reload to try again, or Cancel. Connection details can help diagnose the failure.")
        }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await run(in: webView)
        }
    }

    private func run(in webView: WKWebView) async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard progress.isActive, !Task.isCancelled else { return }
        previousClearanceValues = Set(cookies.filter {
            $0.name == "cf_clearance" && SourceCookiePolicy.matches($0, url: challenge.url)
        }.map(\.value))
        do {
            let request = try SourceVerificationPolicy.request(for: challenge)
            webView.customUserAgent = request.value(forHTTPHeaderField: "User-Agent")
            webView.load(request)
        } catch {
            fail("The verification request could not be prepared. Cancel and try again.")
            return
        }

        let started = ContinuousClock.now
        while progress.isActive, !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard progress.isActive, !Task.isCancelled else { return }
            let elapsed = started.duration(to: .now)
            await checkCompletion(in: webView)
            guard progress.isActive, !Task.isCancelled else { return }

            // Aidoku checks a few seconds after navigation so the widget can render.
            // Also expose a slow page after 12s instead of leaving it hidden forever.
            if !isVisible, elapsed >= .seconds(12) ||
                firstFinish.map({ $0.duration(to: .now) >= .seconds(3) }) == true {
                revealBrowser()
            }
        }
    }

    private func revealBrowser() {
        guard !isVisible, let webView else { return }
        isVisible = true
        NSLayoutConstraint.deactivate(hiddenConstraints)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.layoutIfNeeded()
        onStatus("Complete the website’s verification below. Midoku will retry automatically.")
    }

    private func checkCompletion(in webView: WKWebView) async {
        guard progress.isActive,
              webView.url?.host?.lowercased() == challenge.url.host?.lowercased() else { return }
        let revision = progress.revision
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard progress.isActive, !Task.isCancelled else { return }
        let fresh = SourceCookiePolicy.hasFreshCloudflareClearance(
            in: cookies, for: challenge.url, previousValues: previousClearanceValues
        )
        clearanceState = fresh ? "new" : (cookies.contains {
            $0.name == "cf_clearance" && SourceCookiePolicy.matches($0, url: challenge.url)
        } ? "unchanged" : "absent")
        // This enables an explicit one-time native retry; it does not assert that
        // Cloudflare passed. Automatic completion still requires a finished page.
        onCanTryRequest(fresh)
        guard progress.revision == revision, progress.hasFinishedNavigation, !webView.isLoading else {
            publishDetails()
            return
        }
        let result = try? await webView.evaluateJavaScript(SourceVerificationPolicy.pageStateScript)
        guard progress.isActive, progress.revision == revision, !Task.isCancelled else { return }
        pageState = (result as? String).flatMap {
            ["loading", "challenge", "ready"].contains($0) ? $0 : nil
        } ?? "unavailable"
        publishDetails()
        if progress.complete(revision: revision, hasFreshClearance: fresh, pageState: pageState) {
            timeoutTask?.cancel()
            // Native metadata, images and browser extraction all read this same jar.
            // The request coordinator still retries only once and judges that response.
            onStatus("Checking source access…")
            onVerified()
        }
    }

    private func publishDetails() {
        let http = progress.statusCode.map(String.init) ?? "pending"
        let blocked = blockedLabels.isEmpty ? "" : "\n" + blockedLabels.joined(separator: "\n")
        onDetails("WebKit verification r5\nSession: \(sessions.profileMode.diagnosticName)\nHTTP: \(http) · Page: \(pageState)\nClearance: \(clearanceState)\nLocal frames: \(localFrames) · Cloudflare frames: \(cloudflareFrames)\nBlocked navigations: \(blockedNavigations)\(blocked)")
    }

    private func fail(_ message: String) {
        guard progress.isActive else { return }
        revealBrowser()
        publishDetails()
        onStatus("Verification paused.")
        onError(message)
        stop()
    }

    func stop() {
        progress.stop()
        monitorTask?.cancel()
        monitorTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        // Keep the weak delegate until teardown so a paused page cannot navigate
        // outside the source after a timeout. Inactive attempts cancel navigation.
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard progress.isActive, let url = action.request.url else { return .cancel }
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        guard SourceVerificationPolicy.allowsNavigation(to: url, isMainFrame: isMainFrame, policy: challenge.policy) else {
            blockedNavigations += 1
            let label = SourceVerificationPolicy.navigationLabel(url, isMainFrame: isMainFrame, policy: challenge.policy)
            if !blockedLabels.contains(label), blockedLabels.count < 3 { blockedLabels.append(label) }
            publishDetails()
            return .cancel
        }
        if !isMainFrame {
            if url.scheme == "about" || url.scheme == "blob" { localFrames += 1 }
            if url.host == "challenges.cloudflare.com" { cloudflareFrames += 1 }
        }
        if action.targetFrame == nil {
            webView.load(action.request)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard progress.isActive else { return .cancel }
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
            guard let url = http.url, (try? challenge.policy.validate(url)) != nil else { return .cancel }
            progress.received(statusCode: http.statusCode)
            publishDetails()
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progress.navigationStarted()
        pageState = "loading"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard progress.isActive else { return }
        progress.navigationFinished()
        if firstFinish == nil { firstFinish = .now }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        navigationFailed(error)
    }

    private func navigationFailed(_ error: any Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        // Error descriptions can contain full URLs and credentials; report only a code.
        fail("The verification page could not load (error \(code)). Tap Reload to try again.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("WebKit stopped the verification page. Tap Reload to restart it.")
    }
}
