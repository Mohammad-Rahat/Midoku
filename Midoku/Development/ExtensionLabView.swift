#if DEBUG
import SwiftUI

struct ExtensionLabView: View {
    @State private var output = "Run both bundled fixtures through the JavaScript bridge. No network is used."
    @State private var isRunning = false

    var body: some View {
        List {
            Section("Local adapters") {
                Text(output).font(.body.monospaced()).textSelection(.enabled)
                Button("Run fixture checks") {
                    isRunning = true
                    Task {
                        do {
                            output = try await runFixtures()
                        } catch {
                            output = error.localizedDescription
                        }
                        isRunning = false
                    }
                }
                .disabled(isRunning)
                if isRunning { ProgressView("Running adapters") }
            }
            Section {
                Text("These checks validate extension loading and chapter identities. Library composition, saving, and the reader are separate upcoming milestones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Extension Lab")
    }

    private func runFixtures() async throws -> String {
        let registry = ExtensionRegistry()
        let a = ExtensionManifest(
            id: "dev.midoku.fixture-a", name: "Fixture A", version: "1.0.0",
            contractVersion: 1, domains: [], capabilities: [.search, .feeds, .details, .chapters]
        )
        let b = ExtensionManifest(
            id: "dev.midoku.fixture-b", name: "Fixture B", version: "1.0.0",
            contractVersion: 1, domains: [], capabilities: [.search, .feeds, .details, .chapters]
        )
        try await registry.registerBundled(manifest: a, javaScript: DevelopmentFixtureBundles.sourceA)
        try await registry.registerBundled(manifest: b, javaScript: DevelopmentFixtureBundles.sourceB)
        let sourceA = try await registry.adapter(
            for: SourceConnection(extensionID: a.id, name: a.name), host: FixtureHost()
        )
        let sourceB = try await registry.adapter(
            for: SourceConnection(extensionID: b.id, name: b.name), host: FixtureHost()
        )
        let chaptersA = try await sourceA.chapters(mangaID: "fixture-manga", cursor: nil)
        let chaptersB = try await sourceB.chapters(mangaID: "fixture-manga", cursor: nil)
        guard chaptersA.items.count == 39, chaptersB.items.count == 40,
              !chaptersA.items.contains(where: { $0.number == "21" }),
              chaptersB.items.contains(where: { $0.id == "b:21" }) else {
            throw ExtensionFailure.invalidResponse("Fixture chapter mismatch.")
        }
        return "Fixture A: 39 chapters, missing 21\nFixture B: 40 chapters, includes b:21\nBoth adapters loaded through JavaScriptCore.\nStable source identities verified."
    }
}

nonisolated private struct FixtureHost: ExtensionHost {
    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse {
        throw ExtensionFailure.requestNotAllowed
    }
}
#endif
