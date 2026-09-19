import SwiftUI

struct HistoryCoverView: View {
    let record: ReadingRecord
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @State private var adapter: (any SourceAdapter)?
    @State private var url: URL?
    private var entry: PersonalEntry? {
        let state = settings.snapshot.library
        if let id = record.entryID, let saved = state.entry(id) { return saved }
        guard let listing = state.listings.first(where: { $0.identity == record.identity.listing }) else { return nil }
        return state.entries.first { $0.links.contains { $0.listingID == listing.id } }
    }
    var body: some View {
        Group {
            if let entry { LibraryCoverView(entry: entry, extensions: extensions) }
            else if let adapter { SourceCoverView(url: url, adapter: adapter, extensions: extensions) }
            else { Image("MidokuCoverPlaceholder").resizable().scaledToFit() }
        }.accessibilityHidden(true)
            .task(id: record.identity.listing) {
                guard entry == nil, let connection = extensions.connections.first(where: { $0.id == record.identity.listing.connectionID }) else { return }
                do {
                    let source = try await extensions.adapter(for: connection, interaction: .background)
                    url = record.coverURL ?? settings.snapshot.library.listings.first { $0.identity == record.identity.listing }?.details.coverURL
                    adapter = source
                    if url == nil {
                        let details = try await source.details(mangaID: record.identity.listing.externalID)
                        try Task.checkCancellation()
                        url = details.coverURL
                        settings.update { state in
                            for index in state.history.indices where state.history[index].identity.listing == record.identity.listing {
                                state.history[index].coverURL = details.coverURL
                            }
                        }
                    }
                } catch { /* A missing thumbnail never blocks history. */ }
            }
    }
}
