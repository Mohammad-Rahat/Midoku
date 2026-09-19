#if DEBUG
import SwiftUI

/// Exercises the production source grid without requests or catalogue changes.
struct SourceGridPreview: View {
    let extensions: ExtensionEnvironment
    @State private var adapter: (any SourceAdapter)?
    @State private var error: String?
    var body: some View {
        ScrollView {
            if let adapter {
                MangaResultsGrid(items: ["The quiet adventure", "Blue afternoon", "Paper moons", "The last lantern", "A long way home", "Weekend collection"].enumerated().map {
                    MangaSummary(id: "preview-\($0.offset)", title: $0.element, coverURL: nil)
                }, adapter: adapter, extensions: extensions).padding(16)
            } else if let error { Text(error) }
            else { ProgressView() }
        }.background(MidokuTheme.background).navigationTitle("Source A").navigationBarTitleDisplayMode(.inline)
            .modifier(NativeNavigationBar())
            .task {
                do {
                    let registry = ExtensionRegistry()
                    let manifest = ExtensionManifest(id: "dev.midoku.fixture-a", name: "Source A", version: "1.0.0",
                        contractVersion: 1, domains: [], capabilities: [.search, .feeds, .details, .chapters])
                    try await registry.registerBundled(manifest: manifest, javaScript: DevelopmentFixtureBundles.sourceA)
                    adapter = try await registry.adapter(for: SourceConnection(extensionID: manifest.id, name: manifest.name), host: PreviewHost())
                } catch { self.error = error.localizedDescription }
            }
    }
}
nonisolated private struct PreviewHost: ExtensionHost {
    func request(_ input: SourceHTTPRequest) async throws -> SourceHTTPResponse { throw ExtensionFailure.requestNotAllowed }
}
#endif
