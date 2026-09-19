import AidokuRunner
import Nuke
import SwiftUI

enum MCRequestPurpose {
    @TaskLocal static var thumbnail = false
}

@MainActor
final class MCThumbnailCache {
    static let shared = MCThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private var active = 0
    private var tasks: [UUID: Task<UIImage?, Never>] = [:]
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MidokuChapterThumbnails")

    init() { cache.totalCostLimit = 16 * 1024 * 1024 }

    func image(chapter: MCLibraryChapter, store: MCCollectionStore) async -> UIImage? {
        let key = chapter.id.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let file = directory.appendingPathComponent(chapter.id.uuidString + ".jpg")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { cache.setObject(image, forKey: key, cost: data.count); return image }
        if let task = tasks[chapter.id] { return await task.value }
        guard let physical = store.physical(chapter.identity) else { return nil }
        let task = Task<UIImage?, Never> { [self] in
            while active >= 2 {
                do { try await Task.sleep(nanoseconds: 100_000_000); try Task.checkCancellation() } catch { return nil }
            }
            active += 1
            defer { active -= 1 }
            do {
                let identifier = ChapterIdentifier(sourceKey: physical.manga.sourceKey, mangaKey: physical.manga.key, chapterKey: physical.chapter.key)
                let pages: [AidokuRunner.Page]
                if DownloadManager.shared.isChapterDownloaded(chapter: identifier) {
                    pages = await DownloadManager.shared.getDownloadedPages(for: identifier)
                } else if let source = store.source(chapter.identity.listing.connectionID) {
                    pages = try await MCRequestPurpose.$thumbnail.withValue(true) { try await source.getPageList(manga: physical.manga, chapter: physical.chapter) }
                } else { return nil }
                try Task.checkCancellation()
                guard let page = pages.first else { return nil }
                let image: UIImage
                switch page.content {
                case .url(let url, let context):
                    let request = await ReaderPageView.imageRequest(url: url, context: context, sourceKey: physical.manga.sourceKey)
                    image = try await ImagePipeline.shared.image(for: request)
                case .image(let value): image = value.image
                default: return nil
                }
                try Task.checkCancellation()
                let width: CGFloat = 240
                let scaledHeight = max(1, image.size.height * width / max(1, image.size.width))
                let size = CGSize(width: width, height: min(360, scaledHeight))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: width, height: scaledHeight)) }
                if let data = thumbnail.jpegData(compressionQuality: 0.72) {
                    cache.setObject(thumbnail, forKey: key, cost: data.count)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? data.write(to: file, options: .atomic)
                    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                    if files.count > 250 {
                        let ordered = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
                        for old in ordered.prefix(files.count - 250) { try? FileManager.default.removeItem(at: old) }
                    }
                }
                return thumbnail
            } catch { return nil }
        }
        tasks[chapter.id] = task
        let image = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        tasks[chapter.id] = nil
        return image
    }
}

struct MCChapterThumbnail: View {
    let variant: MCChapterVariant?
    @State private var store = MCCollectionStore.shared
    @State private var image: UIImage?
    @State private var visible = false
    private var chapter: MCLibraryChapter? { variant.flatMap { store.library.chapter($0.chapterID) } }
    private var customImage: UIImage? {
        guard let id = variant?.edits.coverID, let data = store.library.covers.first(where: { $0.id == id })?.data else { return nil }
        return UIImage(data: data)
    }
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = customImage ?? image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let chapter, let thumbnail = store.snapshot.chapters.first(where: { $0.chapterID == chapter.id })?.chapter.thumbnail {
                    SourceImageView(source: store.source(chapter.identity.listing.connectionID), imageUrl: thumbnail,
                        width: geometry.size.width, height: geometry.size.height, placeholder: "MidokuChapterPlaceholder")
                } else { Image("MidokuChapterPlaceholder").resizable().scaledToFill() }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped()
        }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .task(id: "\(variant?.chapterID.uuidString ?? "")-\(visible)") {
            guard visible, customImage == nil, let chapter,
                  store.snapshot.chapters.first(where: { $0.chapterID == chapter.id })?.chapter.thumbnail == nil else { return }
            do { try await Task.sleep(nanoseconds: 300_000_000); try Task.checkCancellation() } catch { return }
            image = await MCThumbnailCache.shared.image(chapter: chapter, store: store)
        }.accessibilityHidden(true)
    }
}
