import SwiftUI

struct PersonalHomeSections: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    private var state: LibraryState { settings.snapshot.library }
    private var recent: [PersonalEntry] { Array(state.entries.filter { $0.lastReadAt != nil }.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.prefix(8)) }
    var body: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick up where you left off").font(.title3.bold()).padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(recent) { entry in
                            if let slotID = state.resumeSlot(entry, positions: settings.snapshot.progress),
                               let slot = entry.slots.first(where: { $0.id == slotID }), let variant = slot.preferred {
                                NavigationLink { LibraryReaderView(entryID: entry.id, initialSlotID: slotID, extensions: extensions) } label: {
                                    ContinueReadingCard(entry: entry, variant: variant, extensions: extensions)
                                        .containerRelativeFrame(.horizontal) { width, _ in max(1, width - 40) }
                                }.buttonStyle(.plain)
                            }
                        }
                    }.scrollTargetLayout().padding(.horizontal, 20)
                }.scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)

            }
        }
        if !state.updates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Library updates").font(.title3.bold())
                    Spacer()
                    Button("Clear") { settings.update { $0.library.updates = [] } }.font(.subheadline)
                }
                ForEach(state.updates.sorted { $0.discoveredAt > $1.discoveredAt }.prefix(10)) { update in
                    if let entry = state.entry(update.entryID), let chapter = state.chapter(update.chapterID) {
                        NavigationLink { LibraryEntryView(entryID: entry.id, extensions: extensions) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) { Text(state.title(entry)).font(.subheadline.weight(.semibold)); Text(chapter.record.title).font(.caption).foregroundStyle(MidokuTheme.secondaryText) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                            }.padding(14).background(MidokuTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 20)
        }
        if recent.isEmpty && state.updates.isEmpty && !state.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your library is ready").font(.title3.bold())
                Text("Open an entry to start reading. Your recent reads and newly discovered chapters will appear here.").font(.callout).foregroundStyle(MidokuTheme.secondaryText)
            }.padding(.horizontal, 20)
        }
    }
}

private struct ContinueReadingCard: View {
    let entry: PersonalEntry
    let variant: ChapterVariant
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dynamicTypeSize) private var textSize
    private var state: LibraryState { settings.snapshot.library }
    private var position: ReadingPosition? {
        guard let identity = state.chapter(variant.chapterID)?.identity else { return nil }
        return settings.snapshot.progress.first { $0.id == identity }
    }
    private var progress: Double {
        guard let position else { return 0 }
        return min(1, Double(position.pageIndex + 1) / Double(max(1, position.pageCount)))
    }
    private var chapterLabel: String { state.number(variant).map { "Chapter \($0)" } ?? "Chapter" }
    private var storyTitle: String {
        let title = state.chapterTitle(variant)
        return title == chapterLabel ? "The story continues." : title
    }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            LibraryCoverView(entry: entry, extensions: extensions)
                .frame(width: 84, height: 126).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 9) {
                Text(state.title(entry).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.tint).lineLimit(2)
                Text(storyTitle).font(.headline).lineLimit(2).foregroundStyle(MidokuTheme.primaryText)
                Text(position.map { "\(chapterLabel) · \($0.pageIndex + 1) of \($0.pageCount) pages" } ?? chapterLabel)
                    .font(.caption).foregroundStyle(MidokuTheme.secondaryText).lineLimit(2)
                ProgressView(value: progress).tint(settings.snapshot.preferences.accent.color)
                    .accessibilityLabel("Chapter progress")
                HStack {
                    Text("Continue reading").font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right").font(.subheadline)
                }.foregroundStyle(.tint).padding(.top, 3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(settings.snapshot.preferences.accent.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
