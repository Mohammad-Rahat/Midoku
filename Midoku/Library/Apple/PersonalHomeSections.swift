import SwiftUI

struct PersonalHomeSections: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    private var state: LibraryState { settings.snapshot.library }
    private var recent: [PersonalEntry] { Array(state.entries.filter { $0.lastReadAt != nil }.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.prefix(8)) }
    var body: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue reading").font(.title3.bold()).padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(recent) { entry in
                            if let slot = state.resumeSlot(entry, positions: settings.snapshot.progress) {
                                NavigationLink { LibraryReaderView(entryID: entry.id, initialSlotID: slot, extensions: extensions) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        LibraryCoverView(entry: entry, extensions: extensions).frame(width: 116, height: 166).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text(state.title(entry)).font(.subheadline.weight(.medium)).lineLimit(2).frame(width: 116, alignment: .leading)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal, 20)
                }
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
