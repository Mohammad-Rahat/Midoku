import Foundation

/// Browser-only permissions. These never expand an extension's native HTTP access.
nonisolated enum SourceVerificationPolicy {
    static func request(for challenge: SourceChallenge) throws -> URLRequest {
        try challenge.policy.validate(challenge.url)
        var request = URLRequest(url: challenge.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        // WebKit owns its Cookie header. Replaying the rejected native snapshot can
        // overwrite cookies delivered by the challenge's redirects or script.
        let headers = challenge.headers.filter {
            ["accept", "accept-language", "referer"].contains($0.key.lowercased())
        }
        try challenge.policy.validate(headers: headers)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let userAgent = challenge.headers.first(where: { $0.key.lowercased() == "user-agent" })?.value {
            guard !userAgent.isEmpty, userAgent.utf8.count <= 4096,
                  !userAgent.contains("\r"), !userAgent.contains("\n") else {
                throw ExtensionFailure.requestNotAllowed
            }
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        return request
    }

    static func allowsNavigation(to url: URL, isMainFrame: Bool, policy: SourceRequestPolicy) -> Bool {
        if (try? policy.validate(url)) != nil { return true }
        guard !isMainFrame else { return false }

        // Turnstile needs both kinds of local frame. Do not send them through the
        // HTTPS-only adapter policy or replace them with a top-level URL load.
        if url.scheme == "about", url.query == nil,
           ["blank", "srcdoc"].contains(url.path) { return true }
        let cloudflare = SourceRequestPolicy(domains: ["challenges.cloudflare.com"])
        if (try? cloudflare.validate(url)) != nil { return true }
        if url.scheme == "blob", let origin = URL(string: String(url.absoluteString.dropFirst(5))) {
            return (try? policy.validate(origin)) != nil || (try? cloudflare.validate(origin)) != nil
        }
        return false
    }

    // Read-only inspection: no injected hooks, spoofed browser APIs or CAPTCHA solving.
    static let pageStateScript = """
    (() => {
        if (document.readyState !== 'complete') return 'loading';
        const title = (document.title || '').trim().toLowerCase();
        const challenge = document.querySelector(
            'input[name="cf-turnstile-response"], #challenge-running, #challenge-stage, ' +
            'form#challenge-form, #challenge-error-title, #challenge-error-text'
        );
        return challenge || title === 'just a moment...' ? 'challenge' : 'ready';
    })()
    """
}

/// Prevents a delayed cookie/DOM callback from completing a cancelled or newer page.
nonisolated struct SourceVerificationProgress {
    private(set) var revision = 0
    private(set) var isActive = true
    private(set) var hasFinishedNavigation = false
    private(set) var statusCode: Int?

    mutating func navigationStarted() {
        revision += 1
        hasFinishedNavigation = false
        statusCode = nil
    }

    mutating func received(statusCode: Int) { self.statusCode = statusCode }
    mutating func navigationFinished() { hasFinishedNavigation = true }

    mutating func stop() {
        isActive = false
        revision += 1
    }

    mutating func complete(revision: Int, hasFreshClearance: Bool, pageState: String?) -> Bool {
        guard isActive, self.revision == revision, hasFinishedNavigation,
              let statusCode, (200..<300).contains(statusCode),
              hasFreshClearance, pageState == "ready" else { return false }
        stop()
        return true
    }
}
