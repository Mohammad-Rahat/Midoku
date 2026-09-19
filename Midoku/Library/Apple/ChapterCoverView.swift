import SwiftUI
import CryptoKit
import ImageIO

/// Disposable first-page thumbnails, keyed by the complete source chapter identity.
/// Custom covers live separately in the library's transactional store and backups.
actor ChapterThumbnailCache {
    static let shared = ChapterThumbnailCache()
    private let directory = URL.cachesDirectory.appending(path: "Midoku/ChapterThumbnails", directoryHint: .isDirectory)

    private func file(_ identity: SourceChapterIdentity) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(identity)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".jpg")
    }
    func read(_ identity: SourceChapterIdentity) -> UIImage? {
        guard let url = try? file(identity),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
              let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return image
    }
    func store(_ image: UIImage, identity: SourceChapterIdentity) {
        guard let original = image.cgImage else { return }
        let width = min(360, original.width)
        let height = max(1, Int(Double(original.height) * Double(width) / Double(max(1, original.width))))
        // Crop tall webtoon pages to their top; this remains the chapter's first image.
        guard let context = CGContext(data: nil, width: width, height: min(height, 540), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.interpolationQuality = .medium
        context.draw(original, in: CGRect(x: 0, y: CGFloat(min(height, 540) - height), width: CGFloat(width), height: CGFloat(height)))
        guard let cgImage = context.makeImage(), let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75), data.count <= 1_048_576 else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(identity), options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            if files.count > 300 {
                let ordered = files.sorted {
                    let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return left < right
                }
                for old in ordered.prefix(files.count - 300) { try? FileManager.default.removeItem(at: old) }
            }
        } catch { /* Thumbnails are disposable; preserve the user's covers and reading data. */ }
    }
}

struct ChapterCoverView: View {
    let identity: SourceChapterIdentity
    let extensions: ExtensionEnvironment
    var overrideID: UUID? = nil
    @Environment(AppSettingsStore.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    @State private var firstPage: UIImage?
    @State private var visible = false

    private var customImage: UIImage? {
        guard let overrideID, let data = settings.snapshot.library.covers.first(where: { $0.id == overrideID })?.data else { return nil }
        return UIImage(data: data)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MidokuTheme.elevated
                if let image = customImage ?? firstPage {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                } else {
                    Image("MidokuChapterPlaceholder").resizable().scaledToFit()
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
            .task(id: "\(identity.listing.connectionID)-\(identity.listing.externalID)-\(identity.externalID)-\(visible)-\(extensions.isReady)-\(overrideID?.uuidString ?? "default")") {
                guard visible, overrideID == nil else { return }
                firstPage = await ChapterThumbnailCache.shared.read(identity)
                if firstPage != nil { return }
                do {
                    // Fast scrolling cancels offscreen work before requesting a page list.
                    try await Task.sleep(for: .milliseconds(250))
                    let image: UIImage
                    if let saved = downloads.items.first(where: { $0.record.id == identity && $0.status == .completed }), let page = saved.pages.first {
                        image = try await downloads.image(page: page, chapterID: saved.id)
                    } else {
                        guard let connection = extensions.connections.first(where: { $0.id == identity.listing.connectionID }) else { return }
                        let adapter = try await extensions.adapter(for: connection, interaction: .background)
                        guard let page = try await adapter.pages(mangaID: identity.listing.externalID, chapterID: identity.externalID).first else { return }
                        try Task.checkCancellation()
                        image = try await extensions.images.image(url: page.url, headers: page.headers, connection: adapter.connection,
                            manifest: adapter.manifest, maximumDimension: 720, interaction: .background)
                    }
                    try Task.checkCancellation()
                    await ChapterThumbnailCache.shared.store(image, identity: identity)
                    firstPage = await ChapterThumbnailCache.shared.read(identity)
                } catch { /* A preview failure never blocks chapter navigation or opens verification. */ }
            }
    }
}
