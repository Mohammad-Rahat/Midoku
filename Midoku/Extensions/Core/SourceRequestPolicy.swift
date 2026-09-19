import Foundation

nonisolated struct SourceRequestPolicy: Sendable {
    let domains: [String]

    static func isPublicHostName(_ host: String) -> Bool {
        guard host == host.lowercased(), host.count <= 253,
              host.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$"#, options: .regularExpression) != nil,
              host.split(separator: ".").allSatisfy({ $0.count <= 63 }),
              host.contains(where: { $0.isLetter }),
              !["localhost", "local", "internal", "home", "lan", "test", "invalid"].contains(host.split(separator: ".").last.map(String.init) ?? "") else {
            return false
        }
        return true
    }

    /// A leading "*." grants only descendants of a reviewed domain, never the domain itself.
    static func isDomainPermission(_ value: String) -> Bool {
        let root = value.hasPrefix("*.") ? String(value.dropFirst(2)) : value
        return isPublicHostName(root)
    }

    private func allows(_ host: String) -> Bool {
        domains.contains { permission in
            guard Self.isDomainPermission(permission) else { return false }
            if permission.hasPrefix("*.") {
                let suffix = String(permission.dropFirst(1))
                return host.hasSuffix(suffix)
            }
            return host == permission
        }
    }

    func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              Self.isPublicHostName(host), allows(host) else {
            throw ExtensionFailure.requestNotAllowed
        }
    }

    func validate(headers: [String: String]) throws {
        let allowed = Set(["accept", "accept-language", "referer"])
        var seen = Set<String>()
        for (name, value) in headers {
            let key = name.lowercased()
            guard allowed.contains(key), seen.insert(key).inserted,
                  value.utf8.count <= 2048, !value.contains("\r"), !value.contains("\n") else {
                throw ExtensionFailure.requestNotAllowed
            }
            if key == "referer" {
                guard let url = URL(string: value) else { throw ExtensionFailure.requestNotAllowed }
                try validate(url)
            }
        }
    }
}

nonisolated struct SourceHTTPRequest: Codable, Sendable {
    let url: URL
    let headers: [String: String]
    var browserScript: String? = nil
}

nonisolated struct SourceHTTPResponse: Codable, Sendable {
    let url: URL
    let status: Int
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var isChallenge: Bool {
        if header("cf-mitigated")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "challenge" {
            return true
        }
        // Legacy fallback is deliberately narrow. An ordinary 403 is not a challenge.
        guard [403, 503].contains(status), header("content-type")?.lowercased().contains("text/html") == true else {
            return false
        }
        let sample = String(decoding: body.prefix(65_536), as: UTF8.self)
        return sample.contains("cf-chl-") || sample.contains("/cdn-cgi/challenge-platform/")
    }
}

nonisolated enum VerificationInteraction: Sendable {
    case foreground, background
}

nonisolated struct SourceChallenge: Identifiable, Sendable {
    let id: UUID
    let connection: SourceConnection
    let url: URL
    let policy: SourceRequestPolicy
    let headers: [String: String]

    init(connection: SourceConnection, url: URL, policy: SourceRequestPolicy, headers: [String: String] = [:]) {
        self.id = UUID()
        self.connection = connection
        self.url = url
        self.policy = policy
        self.headers = headers
    }
}

protocol SourceSessionProviding: Sendable {
    func headers(for url: URL, connectionID: UUID) async throws -> [String: String]
    func receive(_ response: SourceHTTPResponse, connectionID: UUID) async throws
}

protocol ChallengeResolving: Sendable {
    func resolve(_ challenge: SourceChallenge) async throws
}

/// Only for fixtures and deterministic tests. Live adapters use the WebKit session store.
nonisolated struct EmptySourceSession: SourceSessionProviding {
    func headers(for url: URL, connectionID: UUID) async throws -> [String: String] { [:] }
    func receive(_ response: SourceHTTPResponse, connectionID: UUID) async throws {}
}

nonisolated struct UnavailableChallengeResolver: ChallengeResolving {
    func resolve(_ challenge: SourceChallenge) async throws {
        throw ExtensionFailure.verificationRequired
    }
}


