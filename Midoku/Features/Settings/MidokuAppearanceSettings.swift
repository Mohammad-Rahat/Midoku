import SwiftUI

struct MidokuAccentSettingView: View {
    @AppStorage("Appearance.accent") private var accent = MidokuAccent.defaultHex

    var body: some View {
        ColorPicker(
            "Accent color",
            selection: Binding(
                get: { Color(uiColor: MidokuAccent.uiColor(accent)) },
                set: { accent = MidokuAccent.hex($0) }
            ),
            supportsOpacity: false
        )
        .onChange(of: accent) { _, _ in MidokuAccent.applyToWindows() }
    }
}

struct MidokuLibraryLayoutSettingView: View {
    @AppStorage("Midoku.collectionGrid") private var grid = true
    @AppStorage("Appearance.libraryGridStyle") private var style = ChapterGridStyle.standard
    @AppStorage("Appearance.libraryPortraitColumns") private var portraitColumns = 3
    @AppStorage("Appearance.libraryLandscapeColumns") private var landscapeColumns = 5

    var body: some View {
        Picker("Library view", selection: $grid) {
            Text("List").tag(false)
            Text("Grid").tag(true)
        }
        Picker("Grid style", selection: $style) {
            ForEach(ChapterGridStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if grid {
            Stepper("Portrait items per row: \(portraitColumns)", value: $portraitColumns, in: 2...6)
            Stepper("Landscape items per row: \(landscapeColumns)", value: $landscapeColumns, in: 2...10)
        }
    }
}

struct MidokuChapterLayoutSettingView: View {
    @AppStorage("Midoku.chapterGrid") private var grid = false
    @AppStorage("Appearance.chapterGridStyle") private var style = ChapterGridStyle.standard
    @AppStorage("Appearance.chapterPortraitColumns") private var portraitColumns = 3
    @AppStorage("Appearance.chapterLandscapeColumns") private var landscapeColumns = 5
    var body: some View {
        Picker("Chapter view", selection: $grid) {
            Text("List").tag(false)
            Text("Grid").tag(true)
        }
        Picker("Grid style", selection: $style) {
            ForEach(ChapterGridStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if grid {
            Stepper("Portrait items per row: \(portraitColumns)", value: $portraitColumns, in: 2...6)
            Stepper("Landscape items per row: \(landscapeColumns)", value: $landscapeColumns, in: 2...10)
        }
    }
}
