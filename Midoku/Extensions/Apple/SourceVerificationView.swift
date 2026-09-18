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
                    Text("Complete the website’s verification below, then retry your request.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let loadError {
                        Text(loadError).font(.footnote).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                Divider()
                VerificationBrowser(challenge: challenge, sessions: sessions) { message in
                    loadError = message
                }
            }
            .navigationTitle("Verify source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { coordinator.cancel(id: challenge.id) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Retry request") { coordinator.retry(id: challenge.id) }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct VerificationBrowser: UIViewRepresentable {
    let challenge: SourceChallenge
    let sessions: BrowserSessionStore
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(policy: challenge.policy, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = sessions.makeWebView(for: challenge.connection.id)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: challenge.url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let policy: SourceRequestPolicy
        let onError: (String) -> Void

        init(policy: SourceRequestPolicy, onError: @escaping (String) -> Void) {
            self.policy = policy
            self.onError = onError
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            // Cloudflare embeds verification frames. They do not expand the adapter's HTTP permissions.
            if navigationAction.targetFrame?.isMainFrame == false,
               url.scheme == "https", url.host == "challenges.cloudflare.com" {
                return .allow
            }
            guard navigationAction.targetFrame != nil, (try? policy.validate(url)) != nil else {
                return .cancel
            }
            return .allow
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
