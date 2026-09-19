import SwiftUI

struct ReaderChapterNavigation {
    var title: String?
    var previousTitle: String?
    var nextTitle: String?
    var previous: (@MainActor () -> Void)?
    var next: (@MainActor () -> Void)?
}
struct ReaderCoverContext { var entryID: UUID?; var slotID: UUID? }
extension EnvironmentValues {
    @Entry var readerChapterNavigation = ReaderChapterNavigation()
    @Entry var readerCoverContext = ReaderCoverContext()
}
struct ReaderControlsPreference: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

struct ReaderChapterBoundary: View {
    let forward: Bool
    @Environment(\.readerChapterNavigation) private var navigation
    var body: some View {
        if let action = forward ? navigation.next : navigation.previous {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: forward ? "arrow.down.circle" : "arrow.up.circle")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(forward ? "Next chapter" : "Previous chapter").font(.caption)
                        Text((forward ? navigation.nextTitle : navigation.previousTitle) ?? "Chapter").font(.subheadline.weight(.semibold)).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }.padding(16).frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(MidokuTheme.primaryText).background(MidokuTheme.surface)
        }
    }
}

struct ReaderCoverActions: View {
    let image: UIImage
    let identity: SourceChapterIdentity?
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.readerCoverContext) private var context
    @State private var error: String?
    private var targets: [PersonalEntry] {
        settings.snapshot.library.entries.filter { entry in
            (context.entryID == nil || context.entryID == entry.id) && entry.slots.contains { slot in
                (context.slotID == nil || context.slotID == slot.id) && slot.variants.contains { variant in
                    settings.snapshot.library.chapter(variant.chapterID)?.identity == identity && identity != nil
                }
            }
        }
    }
    var body: some View {
        Group {
            if targets.count == 1, let entry = targets.first {
                actions(entry)
            } else {
                ForEach(targets) { entry in Menu(settings.snapshot.library.title(entry)) { actions(entry) } }
            }
        }.alert("Could not save cover", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func actions(_ entry: PersonalEntry) -> some View {
        Group {
            Button("Set as chapter cover", systemImage: "photo") { save(entry.id, chapter: true) }
            Button("Set as entry cover", systemImage: "book.closed") { save(entry.id, chapter: false) }
        }
    }
    private func save(_ entryID: UUID, chapter: Bool) {
        Task {
            do {
                // Downsample before JPEG encoding so tall reader pages remain bounded.
                let scale = min(1, 1000 / max(image.size.width, image.size.height))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let resized = UIGraphicsImageRenderer(size: CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale)), format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))))
                }
                guard let bytes = resized.jpegData(compressionQuality: 0.75) else { throw LibraryFailure.cover }
                let cover = try LibraryCover(data: CoverImportControls.normalized(bytes))
                try await settings.commit { state in
                    let chapterIDs = Set(state.library.chapters.filter { $0.identity == identity }.map(\.id))
                    try state.library.editEntry(entryID) { entry in
                        if chapter {
                            guard let slot = entry.slots.firstIndex(where: { slot in
                                (context.slotID == nil || slot.id == context.slotID) && slot.variants.contains { chapterIDs.contains($0.chapterID) }
                            }), let variant = entry.slots[slot].variants.firstIndex(where: { chapterIDs.contains($0.chapterID) }) else { throw LibraryFailure.stalePreview }
                            entry.slots[slot].variants[variant].edits.coverID = cover.id
                        } else { entry.coverID = cover.id; entry.hidesCover = false }
                    }
                    state.library.covers.append(cover)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// A narrow leading-edge recognizer reserves back navigation even when navigation chrome is hidden.
struct ReaderBackGesture: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            Color.clear.frame(width: 22).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 18).onEnded { value in
                    guard value.translation.width > 65, value.translation.width > abs(value.translation.height) * 1.5 else { return }
                    dismiss()
                })
                .accessibilityHidden(true)
        }
    }
}
