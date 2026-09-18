import Foundation

actor ExtensionRegistry {
    private struct Registration: Sendable {
        let manifest: ExtensionManifest
        let bundle: String
    }

    private let runtime: any ExtensionRuntime
    private var registrations: [String: Registration] = [:]

    init(runtime: any ExtensionRuntime = JavaScriptExtensionRuntime()) {
        self.runtime = runtime
    }

    /// Only called with reviewed resources shipped with the app.
    /// Remote installation needs signature verification/staging before reaching this boundary.
    func registerBundled(manifest: ExtensionManifest, javaScript: String) async throws {
        try await runtime.validate(bundle: javaScript, manifest: manifest)
        guard registrations[manifest.id] == nil else {
            throw ExtensionFailure.invalidManifest("This extension identity is already registered.")
        }
        registrations[manifest.id] = Registration(manifest: manifest, bundle: javaScript)
    }

    func manifests() -> [ExtensionManifest] {
        registrations.values.map(\.manifest).sorted { $0.id < $1.id }
    }

    func adapter(for connection: SourceConnection, host: any ExtensionHost) throws -> any SourceAdapter {
        guard connection.isEnabled, let registration = registrations[connection.extensionID] else {
            throw ExtensionFailure.missingExtension(connection.extensionID)
        }
        return JavaScriptSourceAdapter(
            manifest: registration.manifest, connection: connection,
            bundle: registration.bundle, runtime: runtime, host: host
        )
    }
}

nonisolated private struct JavaScriptSourceAdapter: SourceAdapter {
    let manifest: ExtensionManifest
    let connection: SourceConnection
    let bundle: String
    let runtime: any ExtensionRuntime
    let host: any ExtensionHost

    func search(query: String, cursor: String?, filters: SourceFilterValues) async throws -> SourcePage<MangaSummary> {
        let page: SourcePage<MangaSummary> = try await call("search", capability: .search, input: BrowseInput(query: query, cursor: cursor, filters: filters))
        try validateManga(page.items)
        return page
    }

    private struct BrowseInput: Encodable, Sendable {
        var query: String? = nil
        var feedID: String? = nil
        var cursor: String? = nil
        var filters: SourceFilterValues = [:]
    }

    func searchFilters() async throws -> [SourceSearchFilter] {
        guard manifest.capabilities.contains(.filters) else { return [] }
        let filters: [SourceSearchFilter] = try await call("getSearchFilters", capability: .filters, input: [String: String]())
        try validateIDs(filters.map(\.id))
        guard filters.count <= 32 else { throw ExtensionFailure.responseTooLarge }
        for filter in filters {
            try validateIDs(filter.options.map(\.id))
            let options = Set(filter.options.map(\.id))
            guard !filter.title.isEmpty, !filter.options.isEmpty,
                  !filter.scopes.isEmpty, Set(filter.defaults).count == filter.defaults.count,
                  Set(filter.defaults).isSubset(of: options),
                  !filter.required || !filter.defaults.isEmpty,
                  filter.kind != .single || filter.defaults.count <= 1 else {
                throw ExtensionFailure.invalidResponse("Invalid search filter.")
            }
        }
        return filters
    }

    func feeds() async throws -> [FeedDescriptor] {
        let result: [FeedDescriptor] = try await call("getFeeds", capability: .feeds, input: [String: String]())
        try validateIDs(result.map(\.id))
        return result
    }

    func feed(id: String, cursor: String?, filters: SourceFilterValues) async throws -> SourcePage<MangaSummary> {
        let page: SourcePage<MangaSummary> = try await call("getFeedPage", capability: .feeds, input: BrowseInput(feedID: id, cursor: cursor, filters: filters))
        try validateManga(page.items)
        return page
    }

    func details(mangaID: String) async throws -> MangaDetails {
        let detail: MangaDetails = try await call("getMangaDetails", capability: .details, input: ["mangaID": mangaID])
        try validateIDs([detail.id])
        guard detail.id == mangaID, !detail.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionFailure.invalidResponse("Invalid manga details.")
        }
        if let coverURL = detail.coverURL { try SourceRequestPolicy(domains: manifest.domains).validate(coverURL) }
        if let languages = detail.availableLanguages { try validateIDs(languages.map(\.id)) }
        if let webURL = detail.webURL { try SourceRequestPolicy(domains: manifest.domains).validate(webURL) }
        return detail
    }

    func chapters(mangaID: String, cursor: String?, language: String?) async throws -> SourcePage<ChapterRecord> {
        let page: SourcePage<ChapterRecord> = try await call("getChapterPage", capability: .chapters, input: ["mangaID": mangaID, "cursor": cursor, "language": language])
        try validateIDs(page.items.map(\.id))
        return page
    }

    func pages(mangaID: String, chapterID: String) async throws -> [PageResource] {
        let pages: [PageResource] = try await call("getChapterPages", capability: .pages, input: ["mangaID": mangaID, "chapterID": chapterID])
        try validateIDs(pages.map(\.id))
        let policy = SourceRequestPolicy(domains: manifest.domains)
        for page in pages {
            try policy.validate(page.url)
            try policy.validate(headers: page.headers)
        }
        return pages
    }

    private func call<Result: Decodable & Sendable, Input: Encodable & Sendable>(
        _ method: String, capability: SourceCapability, input: Input
    ) async throws -> Result {
        guard manifest.capabilities.contains(capability) else {
            throw ExtensionFailure.unsupportedMethod(method)
        }
        let arguments = try JSONEncoder().encode(input)
        let data = try await runtime.invoke(bundle: bundle, method: method, input: arguments, host: host)
        do {
            return try JSONDecoder().decode(Result.self, from: data)
        } catch {
            throw ExtensionFailure.invalidResponse("Contract decoding failed.")
        }
    }

    private func validateManga(_ items: [MangaSummary]) throws {
        try validateIDs(items.map(\.id))
        let policy = SourceRequestPolicy(domains: manifest.domains)
        for item in items {
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExtensionFailure.invalidResponse("Empty title.")
            }
            if let url = item.coverURL { try policy.validate(url) }
        }
    }

    private func validateIDs(_ ids: [String]) throws {
        guard ids.count <= 2_000, Set(ids).count == ids.count,
              ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 512 }) else {
            throw ExtensionFailure.invalidResponse("Missing, duplicate, or oversized identifiers.")
        }
    }
}
