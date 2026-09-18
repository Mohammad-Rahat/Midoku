import Foundation

protocol SourceHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SourceHTTPResponse
}

/// Redirects are returned to the coordinator for permission and cookie revalidation.
nonisolated private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

nonisolated final class URLSessionSourceTransport: SourceHTTPTransport, Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SourceHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, let url = response.url else {
            throw ExtensionFailure.invalidResponse("Non-HTTP response.")
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            throw ExtensionFailure.responseTooLarge
        }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumBytes else { throw ExtensionFailure.responseTooLarge }
            body.append(byte)
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return SourceHTTPResponse(url: url, status: response.statusCode, headers: headers, body: body)
    }
}

actor SourceRequestCoordinator {
    private let transport: any SourceHTTPTransport
    private let sessions: any SourceSessionProviding
    private let verification: any ChallengeResolving
    private let minimumSpacing: Duration
    private var activeConnections = Set<UUID>()
    private var nextRequest: [UUID: ContinuousClock.Instant] = [:]

    init(
        transport: any SourceHTTPTransport,
        sessions: any SourceSessionProviding,
        verification: any ChallengeResolving,
        minimumSpacing: Duration = .milliseconds(500)
    ) {
        self.transport = transport
        self.sessions = sessions
        self.verification = verification
        self.minimumSpacing = minimumSpacing
    }

    func request(
        _ input: SourceHTTPRequest,
        connection: SourceConnection,
        manifest: ExtensionManifest,
        interaction: VerificationInteraction
    ) async throws -> SourceHTTPResponse {
        guard connection.isEnabled, connection.extensionID == manifest.id else {
            throw ExtensionFailure.requestNotAllowed
        }
        try manifest.validate()
        let policy = SourceRequestPolicy(domains: manifest.domains)
        try policy.validate(input.url)
        try policy.validate(headers: input.headers)

        // One request/verification flow per connection. Other sources remain independent.
        while activeConnections.contains(connection.id) {
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
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
            let response = try await transport.send(request, maximumBytes: 8 * 1024 * 1024)
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
