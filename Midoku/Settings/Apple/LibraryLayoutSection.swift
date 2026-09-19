import SwiftUI

struct LibraryLayoutSection: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dynamicTypeSize) private var textSize
    private var layout: LibraryLayoutPreferences { settings.snapshot.preferences.resolvedLibraryLayout }

    var body: some View {
        Section {
            if textSize.isAccessibilitySize {
                Picker("Layout", selection: binding(\.style)) {
                    ForEach(LibraryLayoutStyle.allCases) { Text($0.title).tag($0) }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(LibraryLayoutStyle.allCases) { style in
                        Button { settings.update { $0.preferences.libraryLayout = updated(style) } } label: {
                            VStack(spacing: 14) {
                                phone(style).frame(width: 52, height: 94)
                                Text(style.title).font(.subheadline).foregroundStyle(MidokuTheme.primaryText)
                                Image(systemName: layout.style == style ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                            }.frame(maxWidth: .infinity)
                                .foregroundStyle(layout.style == style ? settings.snapshot.preferences.accent.color : MidokuTheme.secondaryText)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(style.title) layout")
                            .accessibilityAddTraits(layout.style == style ? .isSelected : [])
                    }
                }.padding(.vertical, 12)
            }
            if layout.style == .custom {
                Stepper(value: binding(\.portraitColumns), in: 2...6) {
                    LabeledContent("Portrait items per row", value: "\(layout.portraitColumns)")
                }
                Stepper(value: binding(\.landscapeColumns), in: 2...10) {
                    LabeledContent("Landscape items per row", value: "\(layout.landscapeColumns)")
                }
            }
        } header: { Text("Layout") } footer: {
            Text("Swipe left or right in Library to change categories. Standard shows 2 items per row in portrait; Compact shows 3. Custom lets you choose both orientations. Accessibility text uses a list.")
        }.listRowBackground(MidokuTheme.surface)
    }

    private func updated(_ style: LibraryLayoutStyle) -> LibraryLayoutPreferences {
        var value = layout; value.style = style; return value
    }
    private func binding<Value>(_ path: WritableKeyPath<LibraryLayoutPreferences, Value>) -> Binding<Value> {
        Binding(get: { layout[keyPath: path] }, set: { value in
            var updated = layout; updated[keyPath: path] = value
            settings.update { $0.preferences.libraryLayout = updated }
        })
    }
    private func phone(_ style: LibraryLayoutStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).stroke(lineWidth: 2)
            if style == .custom { Image(systemName: "slider.horizontal.3").font(.title2) }
            else {
                let count = style == .standard ? 2 : 3
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: count), spacing: 2) {
                    ForEach(0..<(count * 3), id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill().frame(height: 22) }
                }.padding(6)
            }
        }.accessibilityHidden(true)
    }
}
