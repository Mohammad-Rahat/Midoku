import Foundation
import ImageIO
import UIKit

/// Connection-scoped caches with a separate cover budget, so reader pages cannot evict every cover.
actor SourceImageStore {
    private let requests: SourceRequestCoordinator
    private var generation = UUID()
    private let pages = NSCache<NSString, UIImage>()
    private let covers = NSCache<NSString, UIImage>()
    private let disk = ImageDiskCache(directory: URL.cachesDirectory.appending(path: "Midoku/Covers", directoryHint: .isDirectory))
    private var pending: [String: Task<UIImage, Error>] = [:]

    init(requests: SourceRequestCoordinator) {
        self.requests = requests
        pages.totalCostLimit = 64 * 1024 * 1024; pages.countLimit = 30
        covers.totalCostLimit = 32 * 1024 * 1024; covers.countLimit = 300
    }
    func clear() throws {
        generation = UUID()
        pending.values.forEach { $0.cancel() }; pending.removeAll()
        pages.removeAllObjects(); covers.removeAllObjects()
        try disk.clear()
    }
    func image(url: URL, headers: [String: String], connection: SourceConnection,
               manifest: ExtensionManifest, maximumDimension: Int, interaction: VerificationInteraction = .foreground) async throws -> UIImage {
        let key = ([connection.id.uuidString, manifest.id, manifest.version, url.absoluteString, String(maximumDimension)] +
            headers.keys.sorted().map { "\($0)=\(headers[$0] ?? "")" }).joined(separator: "\n")
        let isCover = maximumDimension <= 720
        let cache = isCover ? covers : pages
        if let image = cache.object(forKey: key as NSString) { return image }
        if isCover, let data = disk.read(key), let image = UIImage(data: data) {
            cache.setObject(image, forKey: key as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count)
            return image
        }
        if let task = pending[key] { return try await task.value }
        let token = generation
        let task = Task {
            let response = try await requests.request(
                SourceHTTPRequest(url: url, headers: headers), connection: connection,
                manifest: manifest, interaction: interaction, kind: .image)
            try Task.checkCancellation()
            let body = try ComixImageDecoder.decode(response, processor: manifest.imageProcessing)
            guard let source = CGImageSourceCreateWithData(body as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                throw ExtensionFailure.invalidResponse("This page is not a supported image.")
            }
            return UIImage(cgImage: cgImage)
        }
        pending[key] = task
        do {
            let image = try await task.value
            if generation == token {
                pending[key] = nil
                cache.setObject(image, forKey: key as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
                if isCover, let data = image.jpegData(compressionQuality: 0.85) { try? disk.store(data, key: key) }
            }
            try Task.checkCancellation()
            return image
        } catch {
            if generation == token { pending[key] = nil }
            throw error
        }
    }
}
