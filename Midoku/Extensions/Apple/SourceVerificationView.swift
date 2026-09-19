import SwiftUI
import WebKit

struct SourceVerificationView: View {
    let challenge: SourceChallenge
    let sessions: BrowserSessionStore
    let coordinator: ChallengeCoordinator
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(challenge.url.host ?? challenge.connection.name)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text("Complete the website’s verification below. Midoku will retry automatically when verification succeeds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let loadError {
                        Text(loadError).font(.footnote).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                Divider()
                VerificationBrowser(
                    challenge: challenge,
                    sessions: sessions,
                    onVerified: { coordinator.retry(id: challenge.id) },
                    onError: { loadError = $0 }
                )
            }
            .navigationTitle("Verify source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { coordinator.cancel(id: challenge.id) }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct VerificationBrowser: UIViewRepresentable {
    let challenge: SourceChallenge
    let sessions: BrowserSessionStore
    let onVerified: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(challenge: challenge, sessions: sessions, onVerified: onVerified, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = sessions.makeVerificationWebView(for: challenge.connection.id)
        webView.navigationDelegate = context.coordinator
        context.coordinator.start(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let challengePageScript = """
        (() => {
            const title = (document.title || '').toLowerCase();
            return Boolean(
                document.querySelector('input[name="cf-turnstile-response"], #challenge-running, #challenge-stage, form#challenge-form, #challenge-error-title, #challenge-error-text') ||
                title === 'just a moment...'
            );
        })()
        """

        let challenge: SourceChallenge
        let sessions: BrowserSessionStore
        let onVerified: () -> Void
        let onError: (String) -> Void
        private var previousClearanceValue: String?
        private var monitorTask: Task<Void, Never>?
        private var didComplete = false

        init(
            challenge: SourceChallenge,
            sessions: BrowserSessionStore,
            onVerified: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.challenge = challenge
            self.sessions = sessions
            self.onVerified = onVerified
            self.onError = onError
        }

        func start(in webView: WKWebView) {
            monitorTask?.cancel()
            monitorTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                await sessions.prepareVerification(for: challenge.url, connectionID: challenge.connection.id)
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                let existing = await cookieStore.allCookies()
                previousClearanceValue = existing.first {
                    $0.name == "cf_clearance" &&
                        SourceCookiePolicy.domainMatches($0, host: challenge.url.host ?? "")
                }?.value
                guard !Task.isCancelled else { return }

                var request = URLRequest(url: challenge.url)
                for (name, value) in challenge.headers {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                if let userAgent = challenge.headers.first(where: {
                    $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame
                })?.value {
                    webView.customUserAgent = userAgent
                }
                webView.load(request)

                while !Task.isCancelled && !didComplete {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await checkCompletion(in: webView)
                }
            }
        }

        func stop() {
            monitorTask?.cancel()
            monitorTask = nil
        }

        private func checkCompletion(in webView: WKWebView) async {
            guard !didComplete else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard SourceCookiePolicy.hasFreshCloudflareClearance(
                in: cookies,
                for: challenge.url,
                previousValue: previousClearanceValue
            ) else { return }
            let result = try? await webView.evaluateJavaScript(Self.challengePageScript)
            guard result as? Bool == false else { return }
            await sessions.importVerificationCookies(for: challenge.url, connectionID: challenge.connection.id)
            didComplete = true
            monitorTask?.cancel()
            onVerified()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            // Cloudflare creates blank documents before attaching its challenge runtime.
            if url.absoluteString == "about:blank" { return .allow }
            // Cloudflare embeds verification frames. They do not expand the adapter's HTTP permissions.
            if url.scheme == "https", url.host == "challenges.cloudflare.com" {
                return .allow
            }
            if navigationAction.targetFrame == nil {
                guard (try? challenge.policy.validate(url)) != nil else { return .cancel }
                webView.load(navigationAction.request)
                return .cancel
            }
            return (try? challenge.policy.validate(url)) != nil ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { await checkCompletion(in: webView) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            if (error as NSError).code != NSURLErrorCancelled {
                onError("The verification page could not load. Cancel and try again.")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            onError("The verification page could not finish loading.")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onError("The verification page stopped. Cancel and try again.")
        }
    }
}
