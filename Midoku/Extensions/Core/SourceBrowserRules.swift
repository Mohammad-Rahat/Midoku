import Foundation

/// WebKit's content-rule regex dialect does not support alternation. Emit one allow rule per host.
nonisolated enum SourceBrowserRules {
    static func encoded(domains: [String]) throws -> String {
        var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block"]]]
        for domain in domains + ["challenges.cloudflare.com"] {
            let host = domain.hasPrefix("*.") ? "[a-z0-9.-]+\\." + NSRegularExpression.escapedPattern(for: String(domain.dropFirst(2))) : NSRegularExpression.escapedPattern(for: domain)
            rules.append(["trigger": ["url-filter": "^https://" + host + "(:443)?/"], "action": ["type": "ignore-previous-rules"]])
        }
        rules.append(["trigger": ["url-filter": ".*", "resource-type": ["image", "media", "font"]], "action": ["type": "block"]])
        return String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
    }
}
