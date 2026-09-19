#if DEBUG
import SwiftUI

struct SourceEntryPreview: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @State private var adapter: (any SourceAdapter)?
    @State private var error: String?
    var body: some View {
        Group {
            if let adapter {
                SourceEntryView(summary: MangaSummary(id: "fixture-manga", title: "The quiet adventure", coverURL: nil),
                    adapter: adapter, extensions: extensions)
            } else if let error { Text(error) }
            else { ProgressView() }
        }.task(id: settings.snapshot.connections) {
            guard let connection = settings.snapshot.connections.first(where: { $0.extensionID == "dev.midoku.fixture-a" && $0.isEnabled }) else { return }
            do { adapter = try await extensions.adapter(for: connection) }
            catch { self.error = error.localizedDescription }
        }
    }
}
#endif
