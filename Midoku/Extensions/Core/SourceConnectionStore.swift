import Foundation

actor SourceConnectionStore {
    private struct Snapshot: Codable {
        let version: Int
        let connections: [SourceConnection]
    }

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> [SourceConnection] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        guard snapshot.version == 1 else {
            throw ExtensionFailure.invalidResponse("Unsupported connection-store version; keep the original file.")
        }
        try validate(snapshot.connections)
        return snapshot.connections
    }

    func save(_ connections: [SourceConnection]) throws {
        try validate(connections)
        let data = try JSONEncoder().encode(Snapshot(version: 1, connections: connections))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func validate(_ connections: [SourceConnection]) throws {
        guard Set(connections.map(\.id)).count == connections.count,
              connections.allSatisfy({ !$0.extensionID.isEmpty && !$0.name.isEmpty }) else {
            throw ExtensionFailure.invalidResponse("Invalid or duplicate source connections.")
        }
    }
}
