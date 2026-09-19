import SwiftUI

/// Global reader preferences apply to direct source reading. Progress is keyed by source identity.
struct SourceChapterReader: View {
    let mangaID: String
    let mangaTitle: String
    let chapter: ChapterRecord
    let adapter: any SourceAdapter
    let extensions: ExtensionEnvironment
    var entryID: UUID? = nil
    var slotID: UUID? = nil
    var coverURL: URL? = nil
    @Environment(\.readerChapterNavigation) private var chapterNavigation
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var pages: [PageResource] = []
    @State private var selectedPage = 0
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var controlsVisible = true
    @State private var showingPreferences = false
    @State private var device = ReaderDeviceController()
    @State private var restoreGeneration: UUID?
    @State private var opened = false
    @State private var positionFraction = 0.0
    @State private var pendingResume: ReaderResumeTarget?
    @State private var scrollSave: Task<Void, Never>?

    @State private var loadedPages: Set<String> = []
    @State private var endVisible = false
    private var preferences: ReaderPreferences { entryID.flatMap { settings.snapshot.library.entry($0)?.readerOverride } ?? settings.snapshot.preferences.reader }
    private var reachedEnd: Bool {
        guard let last = pages.last, loadedPages.contains(last.id), scenePhase == .active else { return false }
        return preferences.mode == .continuous ? endVisible : selectedPage == pages.count - 1
    }
    private var identity: SourceChapterIdentity {
        SourceChapterIdentity(listing: SourceListingIdentity(connectionID: adapter.connection.id, externalID: mangaID), externalID: chapter.id)
    }
    private var prefetchKey: String {
        let current = pages.indices.contains(selectedPage) ? pages[selectedPage].id : ""
        return "\(chapter.id)-\(retry)-\(selectedPage)-\(pages.count)-\(loadedPages.contains(current))-\(scenePhase == .active)"
    }
    private var canvas: Color {
        switch preferences.background { case .black: .black; case .paper: Color(red: 0.98, green: 0.98, blue: 0.96); case .system: MidokuTheme.background }
    }

    var body: some View {
        ReaderChrome(title: chapterNavigation.title ?? chapter.number.map { "Chapter \($0)" } ?? chapter.title,
            subtitle: mangaTitle + " · " + adapter.connection.name,
            visible: controlsVisible || voiceOver, preferences: { showingPreferences = true }, pages: { viewport in
                Group {
                    if let errorMessage { SourceErrorView(message: errorMessage) { retry += 1 } }
                    else if !pages.isEmpty {
                        if preferences.mode == .continuous { continuousPages(viewport: viewport) }
                        else { pagedPages(viewport: viewport) }
                    } else { ProgressView("Loading chapter").frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.background(canvas)
            }, controls: {
                VStack(spacing: 0) {
                    if let message = device.orientationMessage { Text(message).font(.caption).padding(8) }
                    if !pages.isEmpty { pageControls }
                }
            })
        .sheet(isPresented: $showingPreferences) {
            NavigationStack {
                readerSettings.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPreferences = false } } }
            }
        }
        .onAppear { restoreGeneration = settings.restoreGeneration; device.begin(preferences) }
        .onChange(of: preferences) { device.apply(preferences) }
        .onChange(of: scenePhase) {
            if scenePhase == .active { device.apply(preferences) }
            else { savePosition(); device.suspend() }
        }
        .onChange(of: selectedPage) { if preferences.mode != .continuous { positionFraction = 0; savePosition() } }
        .onDisappear { scrollSave?.cancel(); savePosition(); device.end() }
        .task(id: prefetchKey) {
            guard scenePhase == .active, pages.indices.contains(selectedPage),
                  loadedPages.contains(pages[selectedPage].id) else { return }
            let currentPages = pages
            let index = selectedPage
            do {
                let current = try await extensions.adapter(for: adapter.connection, interaction: .background)
                let images = extensions.images
                await ReaderPrefetchWindow.load(currentPages, after: index) { page in
                    _ = try await images.image(url: page.url, headers: page.headers,
                        connection: current.connection, manifest: current.manifest, maximumDimension: 4096,
                        interaction: .background, kind: .prefetch)
                }
            } catch { /* A failed preload is retried normally when its page becomes visible. */ }
        }
        .task(id: reachedEnd) {
            guard reachedEnd else { return }
            do { try await Task.sleep(for: .seconds(1)); try Task.checkCancellation() } catch { return }
            guard restoreGeneration == settings.restoreGeneration else { return }
            settings.update { $0.finished(identity, entryID: entryID, slotID: slotID) }
        }
        .task(id: retry) {
            if !opened {
                settings.update { $0.opened(ReadingRecord(identity: identity, mangaTitle: mangaTitle,
                    sourceName: adapter.connection.name, chapter: chapter, openedAt: Date(), entryID: entryID, slotID: slotID, coverURL: coverURL)) }
                opened = true
            }
            errorMessage = nil
            do {
                let current = try await extensions.adapter(for: adapter.connection)
                let result = try await current.pages(mangaID: mangaID, chapterID: chapter.id)
                try Task.checkCancellation()
                guard !result.isEmpty else { throw ExtensionFailure.invalidResponse("No readable pages.") }
                if let saved = settings.snapshot.progress.first(where: { $0.id == identity }) {
                    selectedPage = result.firstIndex(where: { $0.id == saved.pageID }) ?? min(saved.pageIndex, result.count - 1)
                    positionFraction = saved.fraction
                    pendingResume = ReaderResumeTarget(index: selectedPage, fraction: positionFraction)
                } else { selectedPage = 0; positionFraction = 0 }
                pages = result
            } catch {
                if !Task.isCancelled { errorMessage = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var readerSettings: some View {
        if let entryID, let entry = settings.snapshot.library.entry(entryID), entry.readerOverride != nil {
            EntryReaderSettingsView(entryID: entryID)
        } else { ReaderSettingsView() }
    }

    private func pagedPages(viewport: CGSize) -> some View {
        VStack(spacing: 0) {
            if selectedPage == 0 { ReaderChapterBoundary(forward: false) }
            if pages.indices.contains(selectedPage) {
                let page = pages[selectedPage]
                GeometryReader { pageGeometry in
                ReaderPageImage(index: selectedPage, viewport: pageGeometry.size, preferences: preferences, continuous: false,
                    tap: tapped, loaded: { loadedPages.insert(page.id); savePosition() }, imageLoader: { try await loadImage(page) },
                    swipe: { delta in jump(to: selectedPage + delta) }, identity: identity)
                    .id(page.id)
                }
            }
            if selectedPage == pages.count - 1 { ReaderChapterBoundary(forward: true) }
        }
    }

    private func loadImage(_ page: PageResource) async throws -> UIImage {
        let current = try await extensions.adapter(for: adapter.connection)
        let image = try await extensions.images.image(url: page.url, headers: page.headers,
            connection: current.connection, manifest: current.manifest, maximumDimension: 4096)
        if page.id == pages.first?.id { await ChapterThumbnailCache.shared.store(image, identity: identity) }
        return image
    }

    private func continuousPages(viewport: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ReaderChapterBoundary(forward: false)
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        ReaderPageImage(index: index, viewport: viewport, preferences: preferences, continuous: true,
                                        tap: tapped, loaded: {
                                            loadedPages.insert(page.id)
                                            if let resume = pendingResume, resume.index == index {
                                                Task { @MainActor in
                                                    await Task.yield()
                                                    proxy.scrollTo(resume.index, anchor: UnitPoint(x: 0.5, y: resume.fraction))
                                                    pendingResume = nil
                                                }
                                            }
                                        }, imageLoader: { try await loadImage(page) }, identity: identity)
                            .id(index)
                            .onGeometryChange(for: ReaderPageGeometry.self) { geometry in
                                let frame = geometry.frame(in: .named("readerScroll"))
                                return ReaderPageGeometry(top: frame.minY, height: frame.height)
                            } action: { frame in
                                guard pendingResume == nil, frame.top <= 1, frame.top + frame.height > 1 else { return }
                                selectedPage = index
                                positionFraction = min(1, max(0, -frame.top / max(1, frame.height - viewport.height)))
                                scrollSave?.cancel()
                                scrollSave = Task {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    if !Task.isCancelled { savePosition() }
                                }
                            }
                    }
                    Color.clear.frame(height: 1).onScrollVisibilityChange(threshold: 0.9) { endVisible = $0 }
                    ReaderChapterBoundary(forward: true)
                }
            }
            .coordinateSpace(name: "readerScroll")
            .onAppear {
                let target = pendingResume ?? ReaderResumeTarget(index: selectedPage, fraction: positionFraction)
                proxy.scrollTo(target.index, anchor: UnitPoint(x: 0.5, y: target.fraction))
            }
            .onChange(of: jumpRevision) { proxy.scrollTo(selectedPage, anchor: .top) }
        }
    }

    @State private var jumpRevision = 0
    private var pageControls: some View {
        ReaderPageControls(index: selectedPage, count: pages.count, jump: { jump(to: $0) })
    }
    private func tapped(_ fraction: Double) {
        let action = preferences.tapNavigation ? preferences.tapZones.action(at: fraction, mode: preferences.mode) : 0
        if action == 0 { controlsVisible.toggle() } else { jump(to: selectedPage + action) }
    }
    private func jump(to index: Int) {
        guard pages.indices.contains(index) else {
            if index < 0 { chapterNavigation.previous?() } else { chapterNavigation.next?() }
            return
        }
        pendingResume = nil
        selectedPage = index; positionFraction = 0; jumpRevision += 1
        savePosition()
    }
    private func savePosition() {
        guard restoreGeneration == settings.restoreGeneration, pages.indices.contains(selectedPage) else { return }
        settings.savePosition(ReadingPosition(identity: identity, pageID: pages[selectedPage].id, pageIndex: selectedPage,
            pageCount: pages.count, fraction: positionFraction, updatedAt: Date()))
    }
}

nonisolated private struct ReaderResumeTarget { let index: Int; let fraction: Double }

nonisolated private struct ReaderPageGeometry: Equatable { let top: CGFloat; let height: CGFloat }

struct ReaderPageImage: View {
    let index: Int
    let viewport: CGSize
    let preferences: ReaderPreferences
    let continuous: Bool
    let tap: (Double) -> Void
    let loaded: () -> Void
    let imageLoader: () async throws -> UIImage
    var swipe: (Int) -> Void = { _ in }
    var identity: SourceChapterIdentity? = nil
    @State private var zoomSheet = false
    @State private var image: UIImage?
    @State private var imageAspect: CGFloat?
    @State private var error: String?
    @State private var retry = 0
    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                if continuous {
                    // Vertical pages keep their natural aspect ratio; scaling never reverses their order.
                    pageImage(image).frame(width: viewport.width)
                        .onTapGesture(count: 2) { zoomSheet = true }
                        .onTapGesture { tap(0.5) }
                        .contextMenu {
                            Button("Zoom page", systemImage: "plus.magnifyingglass") { zoomSheet = true }
                            ReaderCoverActions(image: image, identity: identity)
                        }
                        .accessibilityAction(named: "Zoom page") { zoomSheet = true }
                        .accessibilityAction(named: "Show reader controls") { tap(0.5) }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        pageImage(image)
                            .frame(width: baseWidth(image) * zoom)
                            .frame(minWidth: viewport.width, minHeight: viewport.height)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1; gestureZoom = zoom }
                            .onTapGesture { location in
                                if zoom == 1 { tap(location.x / max(1, viewport.width)) }
                                else { tap(0.5) }
                            }
                            .contextMenu { ReaderCoverActions(image: image, identity: identity) }
                            .gesture(MagnifyGesture()
                                .onChanged { zoom = min(4, max(1, gestureZoom * $0.magnification)) }
                                .onEnded { _ in gestureZoom = zoom })
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                        guard zoom == 1, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                        let forward = preferences.mode == .rightToLeft ? value.translation.width > 0 : value.translation.width < 0
                        swipe(forward ? 1 : -1)
                    })
                    .overlay(alignment: .topTrailing) {
                        Menu {
                            Button("Zoom in") { zoom = min(4, zoom + 0.5); gestureZoom = zoom }
                            Button("Zoom out") { zoom = max(1, zoom - 0.5); gestureZoom = zoom }
                            Button("Reset zoom") { zoom = 1; gestureZoom = 1 }
                        } label: {
                            Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44).background(MidokuTheme.surface, in: Circle())
                        }.accessibilityLabel("Page zoom").padding(8)
                    }
                    .scrollDisabled(zoom == 1 && preferences.fit == .screen)
                    .accessibilityAction(named: "Zoom in") { zoom = min(4, zoom + 0.5); gestureZoom = zoom }
                    .accessibilityAction(named: "Zoom out") { zoom = max(1, zoom - 0.5); gestureZoom = zoom }
                }
            } else if let error {
                SourceErrorView(message: error) { retry += 1 }.frame(width: viewport.width, height: placeholderHeight)
            } else {
                ProgressView("Loading page \(index + 1)").frame(width: viewport.width, height: placeholderHeight)
            }
        }
        .onDisappear { image = nil }
        .environment(\.colorScheme, preferences.background == .black ? .dark : (preferences.background == .paper ? .light : nilScheme))
        .sheet(isPresented: $zoomSheet) {
            NavigationStack {
                GeometryReader { geometry in
                    ReaderPageImage(index: index, viewport: geometry.size, preferences: preferences,
                                    continuous: false, tap: { _ in }, loaded: {}, imageLoader: imageLoader, identity: identity)
                }
                .navigationTitle("Page \(index + 1)")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { zoomSheet = false } } }
            }
        }
        .task(id: retry) {
            error = nil
            do {
                let result = try await imageLoader()
                try Task.checkCancellation()
                imageAspect = result.size.width / max(1, result.size.height)
                image = result; loaded()
            } catch {
                if !Task.isCancelled { self.error = error is CancellationError ? "Website verification was cancelled." : error.localizedDescription }
            }
        }
    }
    private var placeholderHeight: CGFloat {
        continuous ? (imageAspect.map { viewport.width / max(0.001, $0) } ?? viewport.height) : viewport.height
    }
    @Environment(\.colorScheme) private var nilScheme
    private func pageImage(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Page \(index + 1)")
    }
    private func baseWidth(_ image: UIImage) -> CGFloat {
        guard preferences.fit == .screen, image.size.height > 0 else { return viewport.width }
        return min(viewport.width, viewport.height * image.size.width / image.size.height)
    }
}
