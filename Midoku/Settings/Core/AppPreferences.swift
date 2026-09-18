import Foundation

nonisolated protocol SettingChoice: RawRepresentable, CaseIterable, Identifiable, Codable, Hashable, Sendable where RawValue == String {
    var title: String { get }
}
extension SettingChoice {
    nonisolated var id: String { rawValue }
}

nonisolated enum AppAppearance: String, SettingChoice {
    case system, light, dark
    var title: String { rawValue.capitalized }
}
nonisolated enum AppAccent: String, SettingChoice {
    case forest, slate, ochre
    var title: String { rawValue.capitalized }
}
nonisolated enum CoverDensity: String, SettingChoice {
    case comfortable, compact
    var title: String { rawValue.capitalized }
    var minimumWidth: Double { self == .compact ? 100 : 140 }
}
nonisolated enum LaunchTab: String, SettingChoice {
    case home, library, browse, history, settings
    var title: String { rawValue.capitalized }
}
nonisolated enum LibrarySort: String, SettingChoice {
    case title, recentlyRead, recentlyAdded, recentlyUpdated
    var title: String {
        switch self {
        case .title: "Title"
        case .recentlyRead: "Recently read"
        case .recentlyAdded: "Recently added"
        case .recentlyUpdated: "Recently updated"
        }
    }
}
nonisolated enum ReaderMode: String, SettingChoice {
    case rightToLeft, leftToRight, continuous
    var title: String {
        switch self {
        case .rightToLeft: "Right to left"
        case .leftToRight: "Left to right"
        case .continuous: "Continuous"
        }
    }
}
nonisolated enum TapZones: String, SettingChoice {
    case edges, wideForward
    var title: String { self == .edges ? "Balanced edges" : "Larger next-page zone" }
    func action(at fraction: Double, mode: ReaderMode) -> Int {
        guard mode != .continuous else { return 0 }
        let position = mode == .rightToLeft ? 1 - fraction : fraction
        if position < 0.25 { return -1 }
        if position > (self == .edges ? 0.75 : 0.5) { return 1 }
        return 0
    }
}
nonisolated enum ReaderFit: String, SettingChoice {
    case width, screen
    var title: String { self == .width ? "Fit width" : "Fit screen" }
}
nonisolated enum ReaderBackground: String, SettingChoice {
    case black, paper, system
    var title: String { rawValue.capitalized }
}
nonisolated enum ReaderOrientation: String, SettingChoice {
    case automatic, portrait, landscape
    var title: String { rawValue.capitalized }
}
nonisolated enum LockDelay: String, SettingChoice {
    case immediately, oneMinute, fiveMinutes
    var seconds: TimeInterval {
        switch self { case .immediately: 0; case .oneMinute: 60; case .fiveMinutes: 300 }
    }
    var title: String {
        switch self { case .immediately: "Immediately"; case .oneMinute: "After 1 minute"; case .fiveMinutes: "After 5 minutes" }
    }
}
nonisolated struct ReaderPreferences: Codable, Equatable, Sendable {
    var mode: ReaderMode = .rightToLeft
    var tapNavigation = true
    var tapZones: TapZones = .edges
    var fit: ReaderFit = .width
    var background: ReaderBackground = .black
    var orientation: ReaderOrientation = .automatic
    var customBrightness = false
    var brightness = 0.6
    var keepAwake = true
}
nonisolated struct AppPreferences: Codable, Equatable, Sendable {
    var appearance: AppAppearance = .system
    var accent: AppAccent = .forest
    var coverDensity: CoverDensity = .comfortable
    var launchTab: LaunchTab = .home
    var librarySort: LibrarySort = .recentlyAdded
    var refreshOnLaunch = true
    var chapterThumbnails = true
    var reader = ReaderPreferences()
    var wifiOnlyDownloads = true
    var appLock = false
    var lockDelay: LockDelay = .immediately
    var protectAppSwitcher = true
    var recordHistory = true
}

nonisolated struct LibraryCategory: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// A saved query, not a frozen list of covers. Array order is the user's Home order.
nonisolated struct HomeSection: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var connectionID: UUID
    var feedID: String?
    var query: String
    var filters: SourceFilterValues
    var sourceTitle: String
    var title: String
    var isVisible = true
    func hasSameQuery(as other: HomeSection) -> Bool {
        connectionID == other.connectionID && feedID == other.feedID && query == other.query &&
        filters.mapValues { $0.sorted() } == other.filters.mapValues { $0.sorted() }
    }
}

nonisolated struct ReadingRecord: Codable, Identifiable, Sendable {
    var id: SourceChapterIdentity { identity }
    let identity: SourceChapterIdentity
    var mangaTitle: String
    var sourceName: String
    var chapter: ChapterRecord
    var openedAt: Date
}
nonisolated struct ReadingPosition: Codable, Identifiable, Sendable {
    var id: SourceChapterIdentity { identity }
    let identity: SourceChapterIdentity
    var pageID: String
    var pageIndex: Int
    var pageCount: Int
    var fraction: Double
    var updatedAt: Date
}

nonisolated struct AppSnapshot: Codable, Sendable {
    var version = 1
    var preferences = AppPreferences()
    var connections: [SourceConnection] = []
    var categories: [LibraryCategory] = []
    var homeSections: [HomeSection] = []
    var history: [ReadingRecord] = []
    var progress: [ReadingPosition] = []

    func validate() throws {
        guard version == 1 else { throw SettingsFailure.futureVersion }
        guard connections.count <= 1000, categories.count <= 1000, homeSections.count <= 500,
              history.count <= 100, progress.count <= 50_000 else { throw SettingsFailure.invalidBackup }
        guard Set(connections.map(\.id)).count == connections.count,
              Set(categories.map(\.id)).count == categories.count,
              Set(categories.map { LibraryCategory.normalized($0.name) }).count == categories.count,
              Set(homeSections.map(\.id)).count == homeSections.count,
              Set(history.map(\.id)).count == history.count,
              Set(progress.map(\.id)).count == progress.count else { throw SettingsFailure.duplicateIdentity }
        guard categories.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }),
              connections.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 100 && !$0.extensionID.isEmpty && $0.extensionID.count <= 200 }),
              preferences.reader.brightness.isFinite, (0.05...1).contains(preferences.reader.brightness) else {
            throw SettingsFailure.invalidBackup
        }
        let sourceIDs = Set(connections.map(\.id))
        for pin in homeSections {
            guard sourceIDs.contains(pin.connectionID), !pin.title.isEmpty, pin.title.count <= 100,
                  pin.sourceTitle.count <= 100, pin.query.count <= 1000, pin.filters.count <= 100,
                  pin.feedID == nil || !(pin.feedID?.isEmpty ?? true),
                  pin.filters.allSatisfy({ $0.key.count <= 200 && $0.value.count <= 200 && $0.value.allSatisfy { $0.count <= 1000 } }) else {
                throw SettingsFailure.invalidBackup
            }
        }
        for record in history {
            guard valid(record.identity, sources: sourceIDs), record.chapter.id == record.identity.externalID,
                  record.mangaTitle.count <= 1000, record.sourceName.count <= 100, record.chapter.title.count <= 1000,
                  record.openedAt.timeIntervalSince1970.isFinite else { throw SettingsFailure.invalidBackup }
        }
        for position in progress {
            guard valid(position.identity, sources: sourceIDs), position.pageIndex >= 0,
                  position.pageCount > position.pageIndex, position.pageCount <= 100_000,
                  position.pageID.count <= 2000, position.fraction.isFinite, (0...1).contains(position.fraction),
                  position.updatedAt.timeIntervalSince1970.isFinite else { throw SettingsFailure.invalidBackup }
        }
    }

    private func valid(_ identity: SourceChapterIdentity, sources: Set<UUID>) -> Bool {
        sources.contains(identity.listing.connectionID) && !identity.listing.externalID.isEmpty &&
        identity.listing.externalID.count <= 2000 && !identity.externalID.isEmpty && identity.externalID.count <= 2000
    }

    mutating func opened(_ record: ReadingRecord) {
        guard preferences.recordHistory else { return }
        history.removeAll { $0.id == record.id }
        history.insert(record, at: 0)
        history = Array(history.sorted(by: Self.historyOrder).prefix(100))
    }

    private static func historyOrder(_ lhs: ReadingRecord, _ rhs: ReadingRecord) -> Bool {
        if lhs.openedAt != rhs.openedAt { return lhs.openedAt > rhs.openedAt }
        let left = [lhs.id.listing.connectionID.uuidString, lhs.id.listing.externalID, lhs.id.externalID]
        let right = [rhs.id.listing.connectionID.uuidString, rhs.id.listing.externalID, rhs.id.externalID]
        return left.lexicographicallyPrecedes(right)
    }

    /// Local edits/progress/preferences win. UUID collisions with another extension are never relinked.
    func merging(_ imported: AppSnapshot) throws -> AppSnapshot {
        var result = self
        for connection in imported.connections {
            if let local = connections.first(where: { $0.id == connection.id }) {
                guard local.extensionID == connection.extensionID else { throw SettingsFailure.identityConflict }
            } else { result.connections.append(connection) }
        }
        let names = Set(categories.map { LibraryCategory.normalized($0.name) })
        result.categories += imported.categories.filter { incoming in
            !categories.contains { $0.id == incoming.id } && !names.contains(LibraryCategory.normalized(incoming.name))
        }
        result.homeSections += imported.homeSections.filter { incoming in
            !homeSections.contains { $0.id == incoming.id || $0.hasSameQuery(as: incoming) }
        }
        result.progress += imported.progress.filter { incoming in !progress.contains { $0.id == incoming.id } }
        var records = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        for record in imported.history where record.openedAt > (records[record.id]?.openedAt ?? .distantPast) { records[record.id] = record }
        result.history = Array(records.values.sorted(by: Self.historyOrder).prefix(100))
        try result.validate()
        return result
    }
}

nonisolated enum SettingsFailure: Error, LocalizedError, Equatable {
    case futureVersion, invalidBackup, duplicateIdentity, identityConflict, tooLarge, storage, emptyName, duplicateName
    var errorDescription: String? {
        switch self {
        case .futureVersion: "This file uses a newer format. Update Midoku before opening it."
        case .invalidBackup: "This is not a complete, valid Midoku settings backup. Your current data has not changed."
        case .duplicateIdentity: "The file contains duplicate records. Your current data has not changed."
        case .identityConflict: "A source identifier belongs to a different extension on this device. These records cannot be safely combined."
        case .tooLarge: "This file is larger than the supported 32 MB backup limit."
        case .storage: "Your changes could not be saved. Check available storage and try again."
        case .emptyName: "Enter a name within the allowed length."
        case .duplicateName: "That name is already in use. Choose another name."
        }
    }
}
