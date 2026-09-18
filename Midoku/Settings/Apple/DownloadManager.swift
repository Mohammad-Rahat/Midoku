import Foundation
import Observation
import Network
import ImageIO
import UIKit

@MainActor
@Observable
final class DownloadManager {
    private(set) var items: [SavedDownload] = []
    private(set) var isReady = false
    private(set) var error: String?
    private(set) var wifi = false
    private(set) var connected = false
    private var storageHealthy = true
    private var active = true
    private var runningID: UUID?
    private var worker: Task<Void, Never>?
    private var revision = 0
    private let extensions: ExtensionEnvironment
    private let monitor = NWPathMonitor()
    let storage = DownloadStorage(root: URL.applicationSupportDirectory.appending(path: "Midoku/Downloads"))
    var waitingForWiFi: Bool { extensions.settings.snapshot.preferences.wifiOnlyDownloads && !wifi }

    init(extensions: ExtensionEnvironment) {
        self.extensions = extensions
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi) && !path.isExpensive
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifi = wifi; self.connected = connected
                self.conditionsChanged()
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.midoku.download-network"))
    }
    func load() async {
        guard !isReady else { return }
        do { items = try await storage.load(); isReady = true; schedule() }
        catch { self.error = "Downloads could not be opened. Existing files were kept. Try reopening Midoku." }
    }
    func enqueue(_ record: ReadingRecord) async {
        guard isReady, !items.contains(where: { $0.record.id == record.id && $0.status != .cancelled }) else { return }
        items.append(SavedDownload(id: UUID(), record: record, status: .queued, pages: [], expectedPages: 0))
        await persist(); schedule()
    }
    func retrySave() async { await persist(); schedule() }
    func setActive(_ value: Bool) {
        active = value
        conditionsChanged()
    }
    func conditionsChanged() {
        if !active || !connected || waitingForWiFi { worker?.cancel() }
        else { schedule() }
    }
    func pause(_ id: UUID) async {
        change(id) { $0.status = .paused; $0.message = nil }
        if runningID == id { worker?.cancel() }
        await persist()
    }
    func resume(_ id: UUID) async {
        guard runningID != id else { return }
        change(id) { $0.status = .queued; $0.message = nil }
        await persist(); schedule()
    }
    func cancel(_ id: UUID) async {
        change(id) { $0.status = .cancelled; $0.message = nil }
        if runningID == id { worker?.cancel() }
        await persist()
    }
    func delete(_ id: UUID) async {
        if runningID == id {
            change(id) { $0.status = .cancelled }
            let task = worker
            task?.cancel()
            await task?.value
        }
        do {
            try await storage.delete(id)
            items.removeAll { $0.id == id }
            await persist()
        } catch { self.error = "The saved chapter could not be deleted. Try again." }
    }
    func clearFinishedFiles() async {
        for item in items where item.id != runningID && [.completed, .failed, .cancelled, .paused].contains(item.status) { await delete(item.id) }
    }
    private func schedule() {
        guard isReady, storageHealthy, worker == nil, active, connected, !waitingForWiFi,
              let next = items.first(where: { $0.status == .queued }) else { return }
        runningID = next.id
        worker = Task { await run(next) }
    }
    private func run(_ job: SavedDownload) async {
        defer { worker = nil; runningID = nil; schedule() }
        do {
            guard let connection = extensions.connections.first(where: { $0.id == job.record.identity.listing.connectionID }) else { throw ExtensionFailure.missingExtension("") }
            let adapter = try await extensions.adapter(for: connection, interaction: .background)
            try Task.checkCancellation()
            change(job.id) { $0.status = .resolving; $0.pages = []; $0.message = nil }
            await persist()
            try Task.checkCancellation()
            let pages = try await adapter.pages(mangaID: job.record.identity.listing.externalID, chapterID: job.record.chapter.id)
            guard !pages.isEmpty, pages.count <= 5000 else { throw ExtensionFailure.invalidResponse("Unsupported page count") }
            try Task.checkCancellation()
            try await storage.begin(job.id)
            try Task.checkCancellation()
            change(job.id) { $0.status = .downloading; $0.expectedPages = pages.count }
            var total = 0
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                guard connected, !waitingForWiFi, active else { throw CancellationError() }
                let current = try await extensions.adapter(for: connection, interaction: .background)
                let response = try await extensions.requests.request(SourceHTTPRequest(url: page.url, headers: page.headers),
                    connection: current.connection, manifest: current.manifest, interaction: .background, kind: .download)
                try Task.checkCancellation()
                let body = response.body
                let valid = await Task.detached {
                    guard let source = CGImageSourceCreateWithData(body as CFData, nil), CGImageSourceGetCount(source) > 0,
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) else { return false }
                    return thumbnail.width > 0 && thumbnail.height > 0 && CGImageSourceGetStatus(source) == .statusComplete
                }.value
                guard valid else { throw ExtensionFailure.invalidResponse("This page is not a valid image.") }
                total += body.count
                guard total <= 1024 * 1024 * 1024 else { throw ExtensionFailure.responseTooLarge }
                let saved = try await storage.write(body, id: job.id, pageID: page.id, index: index)
                change(job.id) { $0.pages.append(saved) }
                await persist()
            }
            try Task.checkCancellation()
            guard let completed = items.first(where: { $0.id == job.id }) else { return }
            try await storage.complete(completed)
            change(job.id) { $0.status = .completed; $0.message = nil }
            await persist()
        } catch {
            if error is CancellationError || Task.isCancelled {
                change(job.id) {
                    if ![.paused, .cancelled].contains($0.status) { $0.status = .queued }
                }
            } else { change(job.id) { $0.status = .failed; $0.message = error is ExtensionFailure ? error.localizedDescription : "Could not save this chapter. Check storage and try again." } }
            await persist()
        }
    }
    private func change(_ id: UUID, _ edit: (inout SavedDownload) -> Void) {
        if let index = items.firstIndex(where: { $0.id == id }) { edit(&items[index]) }
    }
    private func persist() async {
        revision += 1
        do { try await storage.save(items, revision: revision); storageHealthy = true; error = nil }
        catch { storageHealthy = false; self.error = "Download changes could not be saved. Check storage before continuing."; worker?.cancel() }
    }
    func image(page: DownloadPage, chapterID: UUID) async throws -> UIImage {
        let data = try await storage.page(page, in: chapterID)
        return try await Task.detached {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
                throw ExtensionFailure.invalidResponse("This saved page is not readable.")
            }
            return UIImage(cgImage: decoded)
        }.value
    }
}
