import SwiftUI
import UniformTypeIdentifiers

struct AboutSettingsView: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    @State private var diagnostics: String?
    @State private var exporting = false
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    MidokuBrandTile(size: 80)
                    Text("Midoku").font(.largeTitle.bold())
                    Text("A quiet place for your next chapter.").font(.subheadline).foregroundStyle(MidokuTheme.secondaryText)
                    Text(AppBuild.displayVersion).font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            }.listRowBackground(Color.clear)
            Section("Made with") {
                Text("Native SwiftUI, WebKit, JavaScriptCore, ImageIO, and LocalAuthentication.").font(.callout)
                Text("Midoku's original identity and artwork. Manga artwork and pages belong to their respective creators and source providers.")
                    .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                Text("Extension build tools: esbuild (MIT) and TypeScript (Apache 2.0). These development tools are not bundled as app runtimes.")
                    .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
            }.listRowBackground(MidokuTheme.surface)
            Section("Open-source acknowledgements") {
                NavigationLink("Comix protocol and image decoding · Apache 2.0") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "Comix-Apache-2.0", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "Apache License 2.0 — keiyoushi/extensions-source contributors")
                            .font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle("Comix acknowledgements").navigationBarTitleDisplayMode(.inline)
                }
            }
            Section {
                if let url = URL(string: "https://github.com/Mohammad-Rahat/Midoku") { Link("Project & support", destination: url) }
                Button("Preview diagnostics") { diagnostics = report() }
            } header: { Text("Support") } footer: {
                Text("Diagnostics are created locally. They contain app/OS versions, extension versions, and record counts. They exclude titles, search queries, URLs, connection IDs, cookies, and credentials. Nothing is sent automatically.")
            }.listRowBackground(MidokuTheme.surface)
            if let diagnostics {
                Section("Diagnostic preview") {
                    Text(diagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Export these diagnostics") { exporting = true }
                }.listRowBackground(MidokuTheme.surface)
            }
        }.settingsStyle().navigationTitle("About")
            .fileExporter(isPresented: $exporting, document: MidokuExportDocument(data: Data((diagnostics ?? "").utf8)),
                contentType: .plainText, defaultFilename: "Midoku-diagnostics") { _ in }
    }
    private func report() -> String {
        let counts = BackupCounts(settings.snapshot)
        let packages = extensions.available.map { "\($0.id) \($0.version) · contract \($0.contractVersion)" }.sorted().joined(separator: "\n")
        return """
        Midoku \(AppBuild.displayVersion)
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Exported: \(Date().formatted(.iso8601))
        Settings schema: \(settings.snapshot.version)
        Connections: \(counts.sources)
        Categories: \(counts.categories)
        Home sections: \(counts.homeSections)
        History records: \(counts.history)
        Reading positions: \(counts.progress)
        Saved downloads: \(downloads.items.filter { $0.status == .completed }.count)
        Bundled extensions:
        \(packages)
        """
    }
}
