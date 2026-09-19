import Foundation

protocol SourceHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SourceHTTPResponse
}

nonisolated enum SourceRequestKind: Sendable { case metadata, image, download }

actor SourceRequestCoordinator {
    private let transport: any SourceHTTPTransport
    private let sessions: any SourceSessionProviding
    private let verification: any ChallengeResolving
    private let browser: (any SourceBrowserRendering)?
    private let minimumSpacing: Duration
    private var waitingMetadata: [UUID: Int] = [:]
    private var waitingImages: [UUID: Int] = [:]
    private var activeConnections = Set<UUID>()
    private var nextRequest: [UUID: ContinuousClock.Instant] = [:]

    init(
        transport: any SourceHTTPTransport,
        sessions: any SourceSessionProviding,
        verification: any ChallengeResolving,
        minimumSpacing: Duration = .milliseconds(500),
        browser: (any SourceBrowserRendering)? = nil
    ) {
        self.transport = transport
        self.sessions = sessions
        self.verification = verification
        self.minimumSpacing = minimumSpacing
        self.browser = browser
    }

    func request(
        _ input: SourceHTTPRequest,
        connection: SourceConnection,
        manifest: ExtensionManifest,
        interaction: VerificationInteraction,
        kind: SourceRequestKind = .metadata
    ) async throws -> SourceHTTPResponse {
        guard connection.isEnabled, connection.extensionID == manifest.id else {
            throw ExtensionFailure.requestNotAllowed
        }
        try manifest.validate()
        let policy = SourceRequestPolicy(domains: manifest.domains)
        try policy.validate(input.url)
        try policy.validate(headers: input.headers)
        if let script = input.browserScript {
            guard kind == .metadata, manifest.browserRendering == true, browser != nil,
                  !script.isEmpty, script.utf8.count <= 32_768 else { throw ExtensionFailure.requestNotAllowed }
        }

        // One request/verification flow per connection. Other sources remain independent.
        if kind == .metadata { waitingMetadata[connection.id, default: 0] += 1 }
        if kind == .image { waitingImages[connection.id, default: 0] += 1 }
        do {
            while activeConnections.contains(connection.id) ||
                (kind != .metadata && waitingMetadata[connection.id, default: 0] > 0) ||
                (kind == .download && waitingImages[connection.id, default: 0] > 0) {
                try await Task.sleep(for: .milliseconds(20))
            }
            try Task.checkCancellation()
        } catch {
            if kind == .metadata { waitingMetadata[connection.id, default: 0] -= 1 }
            if kind == .image { waitingImages[connection.id, default: 0] -= 1 }
            throw error
        }
        if kind == .metadata { waitingMetadata[connection.id, default: 0] -= 1 }
        if kind == .image { waitingImages[connection.id, default: 0] -= 1 }
        activeConnections.insert(connection.id)
        defer { activeConnections.remove(connection.id) }

        var hasVerified = false
        var redirectCount = 0
        var currentURL = input.url
        while true {
            try Task.checkCancellation()
            try policy.validate(currentURL)
            if let next = nextRequest[connection.id], next > .now {
                try await ContinuousClock().sleep(until: next)
            }
            nextRequest[connection.id] = .now.advanced(by: minimumSpacing)
            var request = URLRequest(url: currentURL)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            // Never forward a source-supplied Referer across an origin-changing redirect.
            for (key, value) in input.headers where
                key.lowercased() != "referer" || currentURL.host == input.url.host {
                request.setValue(value, forHTTPHeaderField: key)
            }
            for (key, value) in try await sessions.headers(for: currentURL, connectionID: connection.id) {
                request.setValue(value, forHTTPHeaderField: key)
            }
            if manifest.imageProcessing == "comix-v1", kind != .metadata,
               URLComponents(url: currentURL, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "v3" }) != true,
               let referer = input.headers.first(where: { $0.key.lowercased() == "referer" })?.value,
               let origin = URL(string: referer), let host = origin.host {
                request.setValue("https://" + host, forHTTPHeaderField: "Origin")
            }
            let response = try await transport.send(request, maximumBytes: (kind == .metadata ? 8 : 32) * 1024 * 1024)
            try Task.checkCancellation()
            try policy.validate(response.url)
            guard response.url == currentURL else {
                throw ExtensionFailure.invalidResponse("Transport followed a redirect unexpectedly.")
            }
            try await sessions.receive(response, connectionID: connection.id)

            if response.isChallenge {
                guard !hasVerified else { throw ExtensionFailure.verificationFailed }
                guard interaction == .foreground else { throw ExtensionFailure.verificationRequired }
                try await verification.resolve(SourceChallenge(connection: connection, url: currentURL, policy: policy))
                hasVerified = true
                continue
            }
            if [301, 302, 303, 307, 308].contains(response.status) {
                guard redirectCount < 5, let location = response.header("location"),
                      let redirected = URL(string: location, relativeTo: currentURL)?.absoluteURL else {
                    throw ExtensionFailure.invalidResponse("Invalid or excessive redirects.")
                }
                try policy.validate(redirected)
                redirectCount += 1
                currentURL = redirected
                continue
            }
            if response.status == 429 {
                let delay = response.header("retry-after").flatMap(Double.init) ?? 30
                nextRequest[connection.id] = .now.advanced(by: .seconds(min(max(delay, 1), 3600)))
                throw ExtensionFailure.rateLimited
            }
            guard (200..<300).contains(response.status) else {
                throw ExtensionFailure.httpStatus(response.status)
            }
            if let script = input.browserScript, let browser {
                do {
                    return try await browser.render(response, script: script, connection: connection, policy: policy)
                } catch ExtensionFailure.verificationRequired {
                    guard !hasVerified else { throw ExtensionFailure.verificationFailed }
                    guard interaction == .foreground else { throw ExtensionFailure.verificationRequired }
                    try await verification.resolve(SourceChallenge(connection: connection, url: currentURL, policy: policy))
                    hasVerified = true
                    continue
                }
            }
            return response
        }
    }
}

protocol ExtensionHost: Sendable {
    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse
}

nonisolated struct NetworkExtensionHost: ExtensionHost {
    let coordinator: SourceRequestCoordinator
    let connection: SourceConnection
    let manifest: ExtensionManifest
    let interaction: VerificationInteraction

    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse {
        try await coordinator.request(input, connection: connection, manifest: manifest, interaction: interaction)
    }
}


/// Reviewed adapters may render source HTML in their connection's existing WebKit profile.
protocol SourceBrowserRendering: Sendable {
    func render(_ response: SourceHTTPResponse, script: String, connection: SourceConnection, policy: SourceRequestPolicy) async throws -> SourceHTTPResponse
}
