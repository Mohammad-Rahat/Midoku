import AidokuRunner
import Foundation
import Nuke
import UIKit

@MainActor
enum MCRemoteCoverLoader {
    static func load(
        _ value: String,
        source: AidokuRunner.Source?,
        store: MCCollectionStore
    ) async throws -> MCLibraryCover {
        guard let url = MCRemoteCoverURL.parse(value) else { throw MCLibraryFailure.coverURL }

        let urlRequest = if let source {
            await source.getModifiedImageRequest(url: url, context: nil)
        } else {
            URLRequest(url: url)
        }
        var processors: [ImageProcessing] = []
        if let source, source.features.processesPages {
            processors.append(PageInterceptorProcessor(source: source, pageContext: nil))
        } else if let source, source.features.processesCovers {
            processors.append(CoverInterceptorProcessor(source: source))
        }
        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors,
            userInfo: [.processesKey: !processors.isEmpty]
        )
        let image = try await ImagePipeline.shared.image(for: request)
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw MCLibraryFailure.cover }
        return try store.saveCover(data: data)
    }
}
