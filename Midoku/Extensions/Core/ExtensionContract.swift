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
    case search, feeds, details, chapters, pages, filters

    var methods: [String] {
        switch self {
        case .search: ["search"]
        case .filters: ["getSearchFilters"]
        case .feeds: ["getFeeds", "getFeedPage"]
        case .details: ["getMangaDetails"]
        case .chapters: ["getChapterPage"]
        case .pages: ["getChapterPages"]
        }
    }
}

nonisolated struct ExtensionManifest: Codable, Equatable, Sendable, Identifiable {
    static let supportedContract = 2
    let id: String
    let name: String
    let version: String
    let contractVersion: Int
    let domains: [String]
    let capabilities: Set<SourceCapability>

    func validate() throws {
        guard (1...Self.supportedContract).contains(contractVersion) else {
            throw ExtensionFailure.incompatibleContract(contractVersion)
        }
        guard contractVersion >= 2 || !capabilities.contains(.filters) else {
            throw ExtensionFailure.invalidManifest("Filters require contract 2.")
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
    var preferredChapterLanguage: String? = nil
}

nonisolated struct MangaDetails: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String
    let coverURL: URL?
    var authors: [String]? = nil
    var artists: [String]? = nil
    var status: String? = nil
    var year: String? = nil
    var tags: [String]? = nil
    var availableLanguages: [SourceFilterOption]? = nil
    var defaultChapterLanguage: String? = nil
    var webURL: URL? = nil
}

nonisolated struct ChapterRecord: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    /// Exact source text; never use floating point for chapter identity or ordering.
    let number: String?
    let ordinal: Int
    let language: String?
    var groups: [String]? = nil
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

typealias SourceFilterValues = [String: [String]]

nonisolated struct SourceFilterOption: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
}

nonisolated struct SourceSearchFilter: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case single, multiple }
    enum Scope: String, Codable, Sendable { case search, feed }
    let id: String
    let title: String
    let kind: Kind
    let options: [SourceFilterOption]
    let defaults: [String]
    let scopes: [Scope]
    let required: Bool
}

protocol SourceAdapter: Sendable {
    var manifest: ExtensionManifest { get }
    var connection: SourceConnection { get }
    func search(query: String, cursor: String?, filters: SourceFilterValues) async throws -> SourcePage<MangaSummary>
    func searchFilters() async throws -> [SourceSearchFilter]
    func feeds() async throws -> [FeedDescriptor]
    func feed(id: String, cursor: String?, filters: SourceFilterValues) async throws -> SourcePage<MangaSummary>
    func details(mangaID: String) async throws -> MangaDetails
    func chapters(mangaID: String, cursor: String?, language: String?) async throws -> SourcePage<ChapterRecord>
    func pages(mangaID: String, chapterID: String) async throws -> [PageResource]
}

extension SourceAdapter {
    func search(query: String, cursor: String?) async throws -> SourcePage<MangaSummary> {
        try await search(query: query, cursor: cursor, filters: [:])
    }

    func feed(id: String, cursor: String?) async throws -> SourcePage<MangaSummary> {
        try await feed(id: id, cursor: cursor, filters: [:])
    }

    func chapters(mangaID: String, cursor: String?) async throws -> SourcePage<ChapterRecord> {
        try await chapters(mangaID: mangaID, cursor: cursor, language: nil)
    }

    func searchFilters() async throws -> [SourceSearchFilter] { [] }
}
