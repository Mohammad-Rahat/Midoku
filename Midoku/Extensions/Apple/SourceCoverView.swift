import SwiftUI

struct SourceCoverView: View {
    let url: URL?
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MidokuTheme.elevated
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Image(decorative: "MidokuCoverPlaceholder").resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            do {
                _ = try await extensions.adapter(for: adapter.connection)
                let loaded = try await extensions.images.image(
                    url: url, headers: [:], connection: adapter.connection,
                    manifest: adapter.manifest, maximumDimension: 512
                )
                try Task.checkCancellation()
                image = loaded
            } catch {
                // Metadata and navigation remain usable if an optional cover is unavailable.
            }
        }
    }
}
