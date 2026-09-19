import Foundation

nonisolated enum SourceCookiePolicy {
    static func domainMatches(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain.lowercased()
        let host = host.lowercased()
        if domain.hasPrefix(".") {
            let suffix = String(domain.dropFirst())
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return host == domain
    }

    static func matches(_ cookie: HTTPCookie, url: URL, now: Date = Date()) -> Bool {
        guard domainMatches(cookie, host: url.host ?? ""),
              !cookie.isSecure || url.scheme == "https",
              cookie.expiresDate.map({ $0 > now }) ?? true else { return false }
        let path = url.path.isEmpty ? "/" : url.path
        return path == cookie.path || (path.hasPrefix(cookie.path) &&
            (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
    }

    static func hasFreshCloudflareClearance(
        in cookies: [HTTPCookie],
        for url: URL,
        previousValue: String?,
        now: Date = Date()
    ) -> Bool {
        hasFreshCloudflareClearance(
            in: cookies, for: url, previousValues: Set(previousValue.map { [$0] } ?? []), now: now
        )
    }

    static func hasFreshCloudflareClearance(
        in cookies: [HTTPCookie],
        for url: URL,
        previousValues: Set<String>,
        now: Date = Date()
    ) -> Bool {
        cookies.contains { cookie in
            cookie.name == "cf_clearance" &&
                !cookie.value.isEmpty && !previousValues.contains(cookie.value) &&
                matches(cookie, url: url, now: now)
        }
    }
}
