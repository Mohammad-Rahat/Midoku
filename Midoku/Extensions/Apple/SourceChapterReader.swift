import SwiftUI

/// Direct source reading; personal-library sequencing and persistent progress remain separate.
struct SourceChapterReader: View {
    let mangaID: String
    let mangaTitle: String
    let chapter: ChapterRecord
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @State private var pages: [PageResource] = []
    @State private var selectedPage = 0
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(mangaTitle).font(.subheadline).lineLimit(2)
                Text(([adapter.connection.name] + (chapter.groups ?? [])).formatted(.list(type: .and)))
                    .font(.caption).foregroundStyle(MidokuTheme.secondaryText).lineLimit(2)
            }
            .padding(8).frame(maxWidth: .infinity).background(MidokuTheme.surface)
            if let errorMessage {
                SourceErrorView(message: errorMessage) { retry += 1 }
                    .environment(\.colorScheme, .dark)
                    .frame(maxHeight: .infinity)
            } else if pages.indices.contains(selectedPage) {
                SourceReaderPage(page: pages[selectedPage], number: selectedPage + 1,
                                 adapter: adapter, extensions: extensions)
                    .id(pages[selectedPage].id)
            } else {
                ProgressView("Loading chapter").tint(.white).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !pages.isEmpty {
                HStack {
                    Button {
                        selectedPage -= 1
                    } label: { Label("Previous page", systemImage: "chevron.left") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .disabled(selectedPage == 0)
                    Spacer()
                    Menu {
                        Picker("Page", selection: $selectedPage) {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                                Text("Page \(index + 1)").tag(index)
                            }
                        }
                    } label: {
                        Text("\(selectedPage + 1) / \(pages.count)")
                            .monospacedDigit().frame(minHeight: 44)
                    }
                    .accessibilityLabel("Page \(selectedPage + 1) of \(pages.count). Choose page")
                    Spacer()
                    Button {
                        selectedPage += 1
                    } label: { Label("Next page", systemImage: "chevron.right") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .disabled(selectedPage + 1 == pages.count)
                }
                .padding(.horizontal, 20).background(MidokuTheme.surface)
            }
        }
        .background(MidokuTheme.readerBackground)
        .navigationTitle(chapter.number.map { "Chapter \($0)" } ?? chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: retry) {
            errorMessage = nil
            do {
                _ = try await extensions.adapter(for: adapter.connection)
                let result = try await adapter.pages(mangaID: mangaID, chapterID: chapter.id)
                try Task.checkCancellation()
                guard !result.isEmpty else { throw ExtensionFailure.invalidResponse("No readable pages.") }
                pages = result
                selectedPage = 0
            } catch {
                if !Task.isCancelled {
                    errorMessage = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription
                }
            }
        }
    }
}

private struct SourceReaderPage: View {
    let page: PageResource
    let number: Int
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width * zoom)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .accessibilityLabel("Page \(number)")
                        .gesture(MagnifyGesture()
                            .onChanged { zoom = min(4, max(1, gestureStartZoom * $0.magnification)) }
                            .onEnded { _ in gestureStartZoom = zoom })
                }
            } else if let errorMessage {
                SourceErrorView(message: errorMessage) { retry += 1 }
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ProgressView("Loading page \(number)")
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .environment(\.colorScheme, .dark)
        .toolbar {
            if image != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Zoom in", systemImage: "plus.magnifyingglass") {
                            zoom = min(4, zoom + 0.5); gestureStartZoom = zoom
                        }
                        .disabled(zoom >= 4)
                        Button("Zoom out", systemImage: "minus.magnifyingglass") {
                            zoom = max(1, zoom - 0.5); gestureStartZoom = zoom
                        }
                        .disabled(zoom <= 1)
                        Button("Fit page width") { zoom = 1; gestureStartZoom = 1 }
                    } label: { Label("Page zoom", systemImage: "plus.magnifyingglass") }
                }
            }
        }
        .task(id: retry) {
            errorMessage = nil
            do {
                _ = try await extensions.adapter(for: adapter.connection)
                let loaded = try await extensions.images.image(
                    url: page.url, headers: page.headers, connection: adapter.connection,
                    manifest: adapter.manifest, maximumDimension: 4096
                )
                try Task.checkCancellation()
                image = loaded
            } catch {
                if !Task.isCancelled {
                    errorMessage = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription
                }
            }
        }
    }
}
