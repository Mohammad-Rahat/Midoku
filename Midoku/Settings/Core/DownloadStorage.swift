import Foundation
import CryptoKit

nonisolated enum DownloadStatus: String, Codable, Sendable {
    case queued, resolving, downloading, paused, completed, failed, cancelled
    var title: String { rawValue.capitalized }
}
nonisolated struct DownloadPage: Codable, Sendable, Identifiable {
    let id: String
    let filename: String
    let byteCount: Int
    let checksum: String
}
nonisolated struct SavedDownload: Codable, Identifiable, Sendable {
    let id: UUID
    let record: ReadingRecord
    var status: DownloadStatus
    var pages: [DownloadPage]
    var expectedPages: Int
    var message: String?
}

actor DownloadStorage {
    private struct Inventory: Codable { let version: Int; let items: [SavedDownload] }
    let root: URL
    private var revision = -1
    init(root: URL) { self.root = root }
    func load() throws -> [SavedDownload] {
        let url = root.appending(path: "inventory.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 16 * 1024 * 1024 else { throw SettingsFailure.tooLarge }
        let inventory = try JSONDecoder().decode(Inventory.self, from: data)
        guard inventory.version == 1, Set(inventory.items.map(\.id)).count == inventory.items.count else { throw SettingsFailure.invalidBackup }
        guard inventory.items.allSatisfy({ item in item.pages.enumerated().allSatisfy { $0.element.filename == "\($0.offset).page" } }) else { throw SettingsFailure.invalidBackup }
        return inventory.items.map { item in
            var item = item
            if !item.pages.isEmpty, item.pages.count == item.expectedPages,
               FileManager.default.fileExists(atPath: directory(item.id, staging: false).path),
               item.pages.allSatisfy({ (try? validated($0, directory: directory(item.id, staging: false))) != nil }) {
                item.status = .completed; item.message = nil
            } else if item.status == .completed {
                item.status = .failed; item.message = "Saved pages are incomplete or damaged. Delete this download and download it again."
            } else if [.resolving, .downloading].contains(item.status) {
                item.status = .paused; item.message = "Interrupted. Resume to try again."
            }
            return item
        }
    }
    func save(_ items: [SavedDownload], revision: Int) throws {
        guard revision >= self.revision else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Inventory(version: 1, items: items))
        try data.write(to: root.appending(path: "inventory.json"), options: .atomic)
        self.revision = revision
    }
    func begin(_ id: UUID) throws {
        let stage = directory(id, staging: true)
        if FileManager.default.fileExists(atPath: stage.path) { try FileManager.default.removeItem(at: stage) }
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var url = stage; try url.setResourceValues(values)
    }
    func write(_ data: Data, id: UUID, pageID: String, index: Int) throws -> DownloadPage {
        let name = "\(index).page"
        try data.write(to: directory(id, staging: true).appending(path: name), options: .atomic)
        return DownloadPage(id: pageID, filename: name, byteCount: data.count, checksum: digest(data))
    }
    func complete(_ item: SavedDownload) throws {
        guard !item.pages.isEmpty, item.pages.count == item.expectedPages else { throw SettingsFailure.invalidBackup }
        for page in item.pages { _ = try validated(page, directory: directory(item.id, staging: true)) }
        let final = directory(item.id, staging: false)
        guard !FileManager.default.fileExists(atPath: final.path) else { throw SettingsFailure.storage }
        try FileManager.default.moveItem(at: directory(item.id, staging: true), to: final)
    }
    func page(_ page: DownloadPage, in id: UUID) throws -> Data { try validated(page, directory: directory(id, staging: false)) }
    func delete(_ id: UUID) throws {
        for staging in [false, true] {
            let url = directory(id, staging: staging)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    func totalBytes() throws -> Int64 {
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if values.isRegularFile == true && values.isSymbolicLink != true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    private func directory(_ id: UUID, staging: Bool) -> URL { root.appending(path: (staging ? "staging-" : "chapter-") + id.uuidString, directoryHint: .isDirectory) }
    private func validated(_ page: DownloadPage, directory: URL) throws -> Data {
        guard page.filename.range(of: #"^[0-9]+\.page$"#, options: .regularExpression) != nil else { throw SettingsFailure.invalidBackup }
        let url = directory.appending(path: page.filename)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size == page.byteCount, size > 0, size <= 32 * 1024 * 1024 else { throw SettingsFailure.invalidBackup }
        let data = try Data(contentsOf: url)
        guard digest(data) == page.checksum else { throw SettingsFailure.invalidBackup }
        return data
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
