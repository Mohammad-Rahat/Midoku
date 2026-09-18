import Foundation

actor HomeFeedCache {
    static let shared = HomeFeedCache()
    struct Entry: Codable, Sendable {
        let section: HomeSection
        let items: [MangaSummary]
        let savedAt: Date
        var isFresh: Bool { Date().timeIntervalSince(savedAt) < 15 * 60 }
    }
    private let directory: URL
    init(directory: URL = URL.cachesDirectory.appending(path: "Midoku/Feeds", directoryHint: .isDirectory)) { self.directory = directory }
    func read(_ section: HomeSection) -> Entry? {
        let url = directory.appending(path: "\(section.id).json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024 * 1024,
              let data = try? Data(contentsOf: url), data.count <= 1024 * 1024,
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.section.hasSameQuery(as: section) else { return nil }
        return entry
    }
    func write(_ items: [MangaSummary], section: HomeSection) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entry = Entry(section: section, items: Array(items.prefix(10)), savedAt: Date())
            let data = try JSONEncoder().encode(entry)
            guard data.count <= 1024 * 1024 else { return }
            try data.write(to: directory.appending(path: "\(section.id).json"), options: .atomic)
        } catch { /* A disposable cache failure must not block a successfully loaded feed. */ }
    }
}
