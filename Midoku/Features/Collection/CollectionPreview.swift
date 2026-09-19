#if DEBUG
import AidokuRunner
import Foundation
import UIKit

@MainActor
enum MCCollectionPreview {
    static var entryID: UUID?
    static func prepare() {
        guard ProcessInfo.processInfo.arguments.contains("--collection-preview") else { return }
        let store = MCCollectionStore.shared
        do {
            try store.change { $0 = MCCollectionSnapshot() }
            let a = AidokuRunner.Manga(sourceKey: "preview.a", key: "book", title: "The Paper Lantern",
                authors: ["Midoku Preview"], description: "An editable edition with chapters collected from different sources.")
            let b = AidokuRunner.Manga(sourceKey: "preview.b", key: "book", title: "The Paper Lantern")
            let id = try store.add(a, chapters: [20, 22, 23, 24].map { .init(key: "c\($0)", title: "Across the quiet city", chapterNumber: Float($0)) }, status: .reading)
            store.copy(manga: b, chapters: [.init(key: "c21", title: "The missing chapter", chapterNumber: 21)])
            try store.change { state in
                try state.library.paste(entryID: id, revision: 0, choices: state.library.pastePreview(entryID: id))
                let category = MCCategory(name: "Reading")
                state.categories = [category, MCCategory(name: "Favorites")]
                try state.library.editEntry(id) { $0.categoryIDs = [category.id] }
                if let data = UIImage(named: "MidokuArtwork")?.jpegData(compressionQuality: 0.6) {
                    let cover = MCLibraryCover(data: data); state.library.covers.append(cover)
                    try state.library.editEntry(id) { entry in
                        entry.coverID = cover.id
                        for i in entry.slots.indices { entry.slots[i].variants[0].edits.coverID = cover.id }
                    }
                }
                for i in state.connections.indices { state.connections[i].name = i == 0 ? "Source A" : "Source B" }
                let other = try state.library.createManual(title: "Weekend reading", description: "Your next collection starts here.")
                if let cover = state.library.covers.first { try state.library.editEntry(other) { $0.coverID = cover.id } }
            }
            entryID = id
        } catch { store.error = error.localizedDescription }
    }
}
#endif
