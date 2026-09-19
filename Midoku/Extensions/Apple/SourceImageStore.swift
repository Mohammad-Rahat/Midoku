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
    private let readerDisk = ImageDiskCache(
        directory: URL.cachesDirectory.appending(path: "Midoku/ReaderPages", directoryHint: .isDirectory),
        maximumBytes: 192 * 1024 * 1024, lifetime: 24 * 60 * 60,
        maximumItemBytes: 32 * 1024 * 1024, fileExtension: "image")
    private let pending = SharedTaskPool<Data>()

    init(requests: SourceRequestCoordinator) {
        self.requests = requests
        pages.totalCostLimit = 64 * 1024 * 1024; pages.countLimit = 30
        covers.totalCostLimit = 32 * 1024 * 1024; covers.countLimit = 300
    }
    func clear() async throws {
        generation = UUID()
        await pending.cancelAll()
        pages.removeAllObjects(); covers.removeAllObjects()
        try disk.clear()
        try readerDisk.clear()
    }
    func image(url: URL, headers: [String: String], connection: SourceConnection,
               manifest: ExtensionManifest, maximumDimension: Int, interaction: VerificationInteraction = .foreground,
               kind: SourceRequestKind = .image) async throws -> UIImage {
        try Task.checkCancellation()
        let key = ([connection.id.uuidString, manifest.id, manifest.version, url.absoluteString, String(maximumDimension)] +
            headers.keys.sorted().map { "\($0)=\(headers[$0] ?? "")" }).joined(separator: "\n")
        let isCover = maximumDimension <= 720
        let cache = isCover ? covers : pages
        if let image = cache.object(forKey: key as NSString) { return image }
        let diskCache = isCover ? disk : readerDisk
        if let data = diskCache.read(key), let image = try? Self.decode(data, maximumDimension: maximumDimension) {
            cache.setObject(image, forKey: key as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count)
            return image
        }
        let token = generation
        let requests = requests
        let fetch: @Sendable () async throws -> Data = {
            let response = try await requests.request(
                SourceHTTPRequest(url: url, headers: headers), connection: connection,
                manifest: manifest, interaction: interaction, kind: kind)
            try Task.checkCancellation()
            return try ComixImageDecoder.decode(response, processor: manifest.imageProcessing)
        }
        let body: Data
        do {
            body = try await pending.value(for: key, operation: fetch)
        } catch ExtensionFailure.verificationRequired where interaction == .foreground {
            // A visible page may have joined a background preload. Only the visible
            // caller may retry with interactive verification; preloads never open it.
            try Task.checkCancellation()
            body = try await pending.value(for: key, operation: fetch)
        }
        try Task.checkCancellation()
        let image = try Self.decode(body, maximumDimension: maximumDimension)
        if generation == token {
            cache.setObject(image, forKey: key as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
            if isCover, let data = image.jpegData(compressionQuality: 0.85) { try? disk.store(data, key: key) }
            else if !isCover { try? readerDisk.store(body, key: key) }
        }
        return image
    }

    nonisolated private static func decode(_ body: Data, maximumDimension: Int) throws -> UIImage {
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
}
