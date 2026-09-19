import SwiftUI

struct ChapterLayoutSection: View {
    @Environment(AppSettingsStore.self) private var settings
    private var layout: ChapterLayoutPreferences { settings.snapshot.preferences.resolvedChapterLayout }
    var body: some View {
        Section("Chapters") {
            SettingPicker(title: "View", selection: binding(\.style))
            Toggle("Show chapter thumbnails", isOn: settings.binding(\.chapterThumbnails))
            if layout.style == .grid {
                Stepper(value: binding(\.portraitColumns), in: 2...6) {
                    LabeledContent("Portrait items per row", value: "\(layout.portraitColumns)")
                }
                Stepper(value: binding(\.landscapeColumns), in: 2...10) {
                    LabeledContent("Landscape items per row", value: "\(layout.landscapeColumns)")
                }
            }
        }.listRowBackground(MidokuTheme.surface)
    }
    private func binding<Value>(_ path: WritableKeyPath<ChapterLayoutPreferences, Value>) -> Binding<Value> {
        Binding(get: { layout[keyPath: path] }, set: { value in
            var updated = layout; updated[keyPath: path] = value
            settings.update { $0.preferences.chapterLayout = updated }
        })
    }
}
