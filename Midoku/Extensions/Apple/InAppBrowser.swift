import SwiftUI
import SafariServices

private struct WebsiteDestination: Identifiable {
    let id = UUID()
    let url: URL
}

struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct InAppBrowserLink: View {
    let url: URL
    let title: String
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label(title, systemImage: "arrow.up.right.square") }
            .disabled(!["https", "http"].contains(url.scheme?.lowercased() ?? ""))
            .sheet(isPresented: $showing) { InAppBrowser(url: url).ignoresSafeArea() }
    }
}

/// Route exact source identities to native entries, with a modal in-app web fallback.
/// No URL guessing, external browser launch, or changes to the personal entry.
struct OriginalListingNavigation: ViewModifier {
    @Binding var listing: LibraryListing?
    let extensions: ExtensionEnvironment
    @State private var destination: LibraryListing?
    @State private var adapter: (any SourceAdapter)?
    @State private var website: WebsiteDestination?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil; adapter = nil } })) {
                if let destination, let adapter {
                    SourceEntryView(summary: MangaSummary(id: destination.identity.externalID,
                        title: destination.details.title, coverURL: destination.details.coverURL), adapter: adapter, extensions: extensions)
                }
            }
            .sheet(item: $website) { InAppBrowser(url: $0.url).ignoresSafeArea() }
            .alert("Unable to open listing", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task(id: listing?.id) {
                guard let requested = listing else { return }
                if let connection = extensions.connections.first(where: { $0.id == requested.identity.connectionID && $0.isEnabled }),
                   let source = try? await extensions.adapter(for: connection), source.manifest.capabilities.contains(.details) {
                    guard !Task.isCancelled else { return }
                    adapter = source; destination = requested
                } else {
                    guard !Task.isCancelled else { return }
                    if let url = requested.details.webURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        website = WebsiteDestination(url: url)
                    } else { error = "Enable this extension to open its entry. No website link is available." }
                }
                listing = nil
            }
    }
}
