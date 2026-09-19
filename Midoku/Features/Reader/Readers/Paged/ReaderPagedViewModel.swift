//
//  ReaderPagedViewModel.swift
//  Midoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AidokuRunner

@MainActor
class ReaderPagedViewModel {
    private let baseSource: AidokuRunner.Source?
    private let baseManga: AidokuRunner.Manga
    var collectionSequence: MCReaderSequence?
    var source: AidokuRunner.Source? { chapter.flatMap { collectionSequence?.route($0)?.source } ?? (collectionSequence == nil ? baseSource : nil) }
    var manga: AidokuRunner.Manga { chapter.flatMap { collectionSequence?.route($0)?.manga } ?? baseManga }
    func physicalIdentifier(key: String) -> ChapterIdentifier {
        collectionSequence?.route(key: key)?.identifier ?? .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: key)
    }
    let temporaryPageStore: ReaderTemporaryPageStore?

    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        temporaryPageStore: ReaderTemporaryPageStore? = nil
    ) {
        self.baseSource = source
        self.baseManga = manga
        self.temporaryPageStore = temporaryPageStore
    }

    func loadPages(chapter: AidokuRunner.Chapter) async {
        let previousChapter = self.chapter
        self.chapter = chapter
        if preloadedChapter == chapter {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            if !pages.isEmpty, let previousChapter {
                preloadedChapter = previousChapter
                preloadedPages = pages
            }
            self.chapter = chapter
            pages = await getPages(chapter: chapter)
        }
    }

    func preload(chapter: AidokuRunner.Chapter) async {
        guard preloadedChapter != chapter else { return }
        preloadedChapter = nil
        preloadedPages = await getPages(chapter: chapter)
        preloadedChapter = chapter
    }

    private func getPages(chapter: AidokuRunner.Chapter) async -> [Page] {
        let route = collectionSequence?.route(chapter)
        let source = route?.source ?? (collectionSequence == nil ? baseSource : nil)
        let manga = route?.manga ?? baseManga
        let physical = route?.chapter ?? chapter
        let sourceId = manga.sourceKey
        let identifier = ChapterIdentifier(
            sourceKey: sourceId,
            mangaKey: manga.key,
            chapterKey: physical.key
        )
        let language = chapter.language ?? source?.languages.first
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            return await DownloadManager.shared.getDownloadedPages(for: identifier)
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.key, language: language)
                }
        } else {
            guard var sourcePages = try? await source?.getPageList(
                manga: manga,
                chapter: physical
            ) else {
                return []
            }

            var pages: [Page] = []
            pages.reserveCapacity(sourcePages.count)

            // iterate in reverse so pages with image data are dropped
            while let sourcePage = sourcePages.popLast() {
                var page = sourcePage.toOld(
                    sourceId: sourceId,
                    chapterId: chapter.key,
                    language: language
                )
                if
                    let temporaryPageStore,
                    let image = page.image,
                    let fileURL = await temporaryPageStore.store(
                        image,
                        chapterKey: chapter.key,
                        pageIndex: sourcePages.count
                    )
                {
                    page.image = nil
                    page.imageURL = fileURL.absoluteString
                }
                pages.append(page)
            }

            return pages.reversed()
        }
    }
}
