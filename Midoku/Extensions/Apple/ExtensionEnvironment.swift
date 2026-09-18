import Foundation
import Observation

/// Future reviewed adapters are registered here, never by source-name branches in views.
nonisolated struct BundledSourceExtension: Sendable {
    let manifest: ExtensionManifest
    let javaScript: String
}

nonisolated enum AppExtensionCatalogue {
    static func load() throws -> [BundledSourceExtension] {
        try BundledExtensionResources.entries.map { resource in
            BundledSourceExtension(
                manifest: try JSONDecoder().decode(ExtensionManifest.self, from: Data(resource.manifestJSON.utf8)),
                javaScript: resource.javaScript
            )
        }
    }
}

@MainActor
@Observable
final class ExtensionEnvironment {
    let registry = ExtensionRegistry()
    let browserSessions = BrowserSessionStore()
    let challenges = ChallengeCoordinator()
    let requests: SourceRequestCoordinator
    let images: SourceImageStore
    let settings: AppSettingsStore
    var connections: [SourceConnection] { settings.snapshot.connections.filter { !$0.isArchived } }
    private(set) var available: [ExtensionManifest] = []
    private(set) var errorMessage: String?
    private(set) var isReady = false
    private var isLoading = false

    init(settings: AppSettingsStore) {
        self.settings = settings
        requests = SourceRequestCoordinator(
            transport: URLSessionSourceTransport(),
            sessions: browserSessions,
            verification: challenges
        )
        images = SourceImageStore(requests: requests)
    }

    func load() async {
        guard !isReady, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Load first: an invalid persisted store must not be overwritten with empty data.
            await settings.load()
            guard settings.isReady else { isLoading = false; return }
            let existing = Set(await registry.manifests().map(\.id))
            for source in try AppExtensionCatalogue.load() where !existing.contains(source.manifest.id) {
                try await registry.registerBundled(manifest: source.manifest, javaScript: source.javaScript)
            }
            available = await registry.manifests()
            errorMessage = nil
            isReady = true
        } catch {
            errorMessage = "Extensions could not be loaded. Your saved connections have been preserved."
        }
    }

    func add(_ manifest: ExtensionManifest) async {
        guard isReady, available.contains(where: { $0.id == manifest.id }) else { return }
        let connection = SourceConnection(extensionID: manifest.id, name: manifest.name)
        settings.update { $0.connections.append(connection) }
    }

    func setEnabled(_ enabled: Bool, connectionID: UUID) async {
        guard isReady else { return }
        var updated = settings.snapshot.connections
        guard let index = updated.firstIndex(where: { $0.id == connectionID }) else { return }
        updated[index].isEnabled = enabled
        settings.update { $0.connections = updated }
    }

    func adapter(for connection: SourceConnection, interaction: VerificationInteraction = .foreground) async throws -> any SourceAdapter {
        guard let current = connections.first(where: { $0.id == connection.id }), current.isEnabled,
              let manifest = available.first(where: { $0.id == current.extensionID }) else {
            throw ExtensionFailure.missingExtension(connection.extensionID)
        }
        return try await registry.adapter(for: current, host: NetworkExtensionHost(
            coordinator: requests, connection: current, manifest: manifest, interaction: interaction
        ))
    }

    func rename(_ connection: SourceConnection, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { return }
        settings.update { state in
            if let index = state.connections.firstIndex(where: { $0.id == connection.id }) { state.connections[index].name = trimmed }
        }
    }

    func archive(_ connection: SourceConnection) async {
        settings.update { state in
            if let index = state.connections.firstIndex(where: { $0.id == connection.id }) {
                state.connections[index].isEnabled = false
                state.connections[index].isArchived = true
            }
        }
        await images.clear()
    }

    func restoreConnection(_ connection: SourceConnection) {
        settings.update { state in
            if let index = state.connections.firstIndex(where: { $0.id == connection.id }) {
                state.connections[index].isArchived = false
                state.connections[index].isEnabled = true
            }
        }
    }
}
