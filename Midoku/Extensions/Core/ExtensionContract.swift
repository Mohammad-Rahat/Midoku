import Foundation

nonisolated enum ExtensionFailure: Error, LocalizedError, Equatable, Sendable {
    case invalidManifest(String)
    case incompatibleContract(Int)
    case missingExtension(String)
    case unsupportedMethod(String)
    case invalidResponse(String)
    case requestNotAllowed
    case responseTooLarge
    case httpStatus(Int)
    case rateLimited
    case verificationRequired
    case verificationFailed
    case runtimeFailure
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason): "Invalid extension: \(reason)"
        case .incompatibleContract(let version): "Unsupported extension contract: \(version)."
        case .missingExtension: "This extension is not installed."
        case .unsupportedMethod: "This extension does not support that feature."
        case .invalidResponse: "The source returned content this extension could not read."
        case .requestNotAllowed: "The extension requested an address or header outside its permissions."
        case .responseTooLarge: "The source response exceeds the supported size."
        case .httpStatus(let status): "The source returned an HTTP \(status) error."
        case .rateLimited: "The source is receiving too many requests. Try again later."
        case .verificationRequired: "Open this source to complete website verification."
        case .verificationFailed: "The source still requires verification. Try again later."
        case .runtimeFailure: "The extension could not complete this request."
        case .timedOut: "The extension took too long to respond."
        }
    }
}

nonisolated enum SourceCapability: String, Codable, Hashable, Sendable {
    case search, feeds, details, chapters, pages

    var methods: [String] {
        switch self {
        case .search: ["search"]
        case .feeds: ["getFeeds", "getFeedPage"]
        case .details: ["getMangaDetails"]
        case .chapters: ["getChapterPage"]
        case .pages: ["getChapterPages"]
        }
    }
}

nonisolated struct ExtensionManifest: Codable, Equatable, Sendable, Identifiable {
    static let supportedContract = 1
    let id: String
    let name: String
    let version: String
    let contractVersion: Int
    let domains: [String]
    let capabilities: Set<SourceCapability>

    func validate() throws {
        guard contractVersion == Self.supportedContract else {
            throw ExtensionFailure.incompatibleContract(contractVersion)
        }
        guard id.range(of: #"^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$"#, options: .regularExpression) != nil,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              version.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil,
              !capabilities.isEmpty, domains.count <= 32 else {
            throw ExtensionFailure.invalidManifest("Check identity, name, release version, and capabilities.")
        }
        guard Set(domains).count == domains.count, domains.allSatisfy(SourceRequestPolicy.isDomainPermission) else {
            throw ExtensionFailure.invalidManifest("Use distinct lowercase hosts or reviewed *.domain permissions.")
        }
    }
}

/// This UUID identifies a source configuration/account, not an extension release.
nonisolated struct SourceConnection: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let extensionID: String
    var name: String
    var isEnabled: Bool

    init(id: UUID = UUID(), extensionID: String, name: String, isEnabled: Bool = true) {
        self.id = id
        self.extensionID = extensionID
        self.name = name
        self.isEnabled = isEnabled
    }
}

nonisolated struct SourceListingIdentity: Codable, Hashable, Sendable {
    let connectionID: UUID
    let externalID: String
}

nonisolated struct SourceChapterIdentity: Codable, Hashable, Sendable {
    let listing: SourceListingIdentity
    let externalID: String
}

nonisolated struct SourcePage<Item: Codable & Sendable>: Codable, Sendable {
    let items: [Item]
    let nextCursor: String?
}

nonisolated struct MangaSummary: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let coverURL: URL?
}

nonisolated struct MangaDetails: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String
    let coverURL: URL?
}

nonisolated struct ChapterRecord: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    /// Exact source text; never use floating point for chapter identity or ordering.
    let number: String?
    let ordinal: Int
    let language: String?
}

nonisolated struct PageResource: Codable, Sendable, Identifiable {
    let id: String
    let url: URL
    let headers: [String: String]
}

nonisolated struct FeedDescriptor: Codable, Sendable, Identifiable {
    let id: String
    let title: String
}

protocol SourceAdapter: Sendable {
    var manifest: ExtensionManifest { get }
    var connection: SourceConnection { get }
    func search(query: String, cursor: String?) async throws -> SourcePage<MangaSummary>
    func feeds() async throws -> [FeedDescriptor]
    func feed(id: String, cursor: String?) async throws -> SourcePage<MangaSummary>
    func details(mangaID: String) async throws -> MangaDetails
    func chapters(mangaID: String, cursor: String?) async throws -> SourcePage<ChapterRecord>
    func pages(mangaID: String, chapterID: String) async throws -> [PageResource]
}
