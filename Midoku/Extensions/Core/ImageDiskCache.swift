import Foundation
import CryptoKit

/// Disposable image bytes. Never stores cookies, library edits, or offline downloads.
nonisolated struct ImageDiskCache: Sendable {
    let directory: URL
    var maximumBytes = 128 * 1024 * 1024
    var lifetime: TimeInterval = 30 * 24 * 60 * 60
    var maximumItemBytes = 2 * 1024 * 1024
    var fileExtension = "jpg"

    func file(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + "." + fileExtension)
    }
    func read(_ key: String, now: Date = Date()) -> Data? {
        let url = file(for: key)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let modified = values.contentModificationDate, now.timeIntervalSince(modified) < lifetime,
              let count = values.fileSize, count > 0, count <= maximumItemBytes,
              let data = try? Data(contentsOf: url) else { try? FileManager.default.removeItem(at: url); return nil }
        return data
    }
    func store(_ data: Data, key: String) throws {
        guard !data.isEmpty, data.count <= min(maximumBytes, maximumItemBytes) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: key), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        let sizes = files.compactMap { url -> (URL, Int, Date)? in
            guard let value = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, value.fileSize ?? 0, value.contentModificationDate ?? .distantPast)
        }
        var total = sizes.reduce(0) { $0 + $1.1 }
        for item in sizes.sorted(by: { $0.2 < $1.2 }) where total > maximumBytes {
            try FileManager.default.removeItem(at: item.0); total -= item.1
        }
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
