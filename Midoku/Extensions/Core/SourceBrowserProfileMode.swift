import Foundation

/// LiveContainer virtualizes persistent WebKit cookie paths. Keep each guest
/// connection in its own retained memory store so verification, metadata and
/// images use the same cookie jar without depending on those filesystem hooks.
nonisolated enum SourceBrowserProfileMode: Sendable {
    case persistent, temporary

    static var current: Self { selected(environment: ProcessInfo.processInfo.environment) }

    static func selected(environment: [String: String]) -> Self {
        let isGuest = ["LC_HOME_PATH", "LP_HOME_PATH"].contains {
            environment[$0].map { !$0.isEmpty } ?? false
        }
        return isGuest ? .temporary : .persistent
    }

    var diagnosticName: String {
        switch self {
        case .persistent: "persistent"
        case .temporary: "temporary"
        }
    }
}
