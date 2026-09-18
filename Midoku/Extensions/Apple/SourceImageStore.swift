import Foundation
import ImageIO
import UIKit

/// Connection-scoped, bounded memory cache. All bytes still pass through the source coordinator.
actor SourceImageStore {
    private let requests: SourceRequestCoordinator
    private let cache = NSCache<NSString, UIImage>()

    init(requests: SourceRequestCoordinator) {
        self.requests = requests
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 150
    }

    func image(url: URL, headers: [String: String], connection: SourceConnection,
               manifest: ExtensionManifest, maximumDimension: Int) async throws -> UIImage {
        let key = ([connection.id.uuidString, url.absoluteString, String(maximumDimension)] +
            headers.keys.sorted().map { "\($0)=\(headers[$0] ?? "")" }).joined(separator: "\n") as NSString
        if let image = cache.object(forKey: key) { return image }
        let response = try await requests.request(
            SourceHTTPRequest(url: url, headers: headers), connection: connection,
            manifest: manifest, interaction: .foreground, kind: .image
        )
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(response.body as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw ExtensionFailure.invalidResponse("This page is not a supported image.")
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
