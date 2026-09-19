import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct EntryEditor: View {
    @State var entry: PersonalEntry
    var isNew = false
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var coverData: Data?
    @State private var error: String?
    @State private var saving = false
    private var inherited: MangaDetails? { settings.snapshot.library.listing(entry.primaryListingID)?.details }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: Binding(get: { entry.titleOverride ?? inherited?.title ?? "" }, set: { entry.titleOverride = $0 }))
                    TextField("Author", text: Binding(get: { entry.authorOverride ?? inherited?.authors?.joined(separator: ", ") ?? "" }, set: { entry.authorOverride = $0 }))
                    TextField("Description", text: Binding(get: { entry.descriptionOverride ?? inherited?.description ?? "" }, set: { entry.descriptionOverride = $0 }), axis: .vertical).lineLimit(4...10)
                    if inherited != nil {
                        Menu("Reset fields to source", systemImage: "arrow.uturn.backward") {
                            Button("Title") { entry.titleOverride = nil }
                            Button("Author") { entry.authorOverride = nil }
                            Button("Description") { entry.descriptionOverride = nil }
                        }
                    }
                } footer: { Text("Your edits belong to this entry and survive refreshes. Clearing the description keeps it deliberately blank.") }.listRowBackground(MidokuTheme.surface)
                Section("Cover") {
                    HStack {
                        if let coverData, let image = UIImage(data: coverData) { Image(uiImage: image).resizable().scaledToFit().frame(width: 90, height: 130) }
                        else { LibraryCoverView(entry: entry, extensions: extensions).frame(width: 90, height: 130).clipped().clipShape(RoundedRectangle(cornerRadius: 8)) }
                        CoverImportControls(data: $coverData, error: $error)
                    }
                    Button("Use source cover") { coverData = nil; entry.coverID = nil; entry.hidesCover = false }
                    Button("Use placeholder") { coverData = nil; entry.coverID = nil; entry.hidesCover = true }
                }.listRowBackground(MidokuTheme.surface)
                Section("Your library") {
                    Picker("Reading status", selection: $entry.status) { ForEach(PersonalStatus.allCases) { Text($0.title).tag($0) } }
                    ForEach(settings.snapshot.categories) { category in
                        Toggle(category.name, isOn: Binding(get: { entry.categoryIDs.contains(category.id) }, set: { if $0 { entry.categoryIDs.insert(category.id) } else { entry.categoryIDs.remove(category.id) } }))
                    }
                    NavigationLink("Manage categories") { CategoriesSettingsView() }
                }.listRowBackground(MidokuTheme.surface)
                Section {
                    Toggle("Use custom reader preferences", isOn: Binding(get: { entry.readerOverride != nil }, set: { entry.readerOverride = $0 ? settings.snapshot.preferences.reader : nil }))
                    if entry.readerOverride != nil {
                        SettingPicker(title: "Reading mode", selection: readerBinding(\.mode))
                        SettingPicker(title: "Fit", selection: readerBinding(\.fit))
                        SettingPicker(title: "Background", selection: readerBinding(\.background))
                        SettingPicker(title: "Orientation", selection: readerBinding(\.orientation))
                        Toggle("Keep screen awake", isOn: readerBinding(\.keepAwake))
                        Toggle("Tap to navigate", isOn: readerBinding(\.tapNavigation))
                        SettingPicker(title: "Tap zones", selection: readerBinding(\.tapZones))
                    }
                } header: { Text("Reader") } footer: { Text("Custom preferences apply when reading within this entry, including its copied chapters.") }.listRowBackground(MidokuTheme.surface)
                if let error { Text(error).foregroundStyle(MidokuTheme.danger) }
            }.settingsStyle().navigationTitle(isNew ? "New entry" : "Edit details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving) }.sharedBackgroundVisibility(.hidden)
                }
        }.interactiveDismissDisabled(saving)
    }
    private func readerBinding<Value>(_ key: WritableKeyPath<ReaderPreferences, Value>) -> Binding<Value> {
        Binding(get: { (entry.readerOverride ?? settings.snapshot.preferences.reader)[keyPath: key] }, set: { value in
            var preferences = entry.readerOverride ?? settings.snapshot.preferences.reader
            preferences[keyPath: key] = value; entry.readerOverride = preferences
        })
    }
    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                var candidate = entry
                if let title = candidate.titleOverride { candidate.titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard !(candidate.titleOverride ?? inherited?.title ?? "").isEmpty else { throw LibraryFailure.emptyTitle }
                candidate.categoryIDs.formIntersection(settings.snapshot.categories.map(\.id))
                let cover = coverData.map { LibraryCover(data: $0) }
                if let cover { candidate.coverID = cover.id; candidate.hidesCover = false }
                try await settings.commit { state in
                    if let cover { state.library.covers.append(cover) }
                    if isNew { state.library.entries.append(candidate) }
                    else {
                        // Save editable fields only; refresh, progress and sequence changes stay intact.
                        try state.library.editEntry(candidate.id) { current in
                            current.titleOverride = candidate.titleOverride; current.descriptionOverride = candidate.descriptionOverride
                            current.authorOverride = candidate.authorOverride; current.coverID = candidate.coverID; current.hidesCover = candidate.hidesCover
                            current.categoryIDs = candidate.categoryIDs; current.status = candidate.status; current.readerOverride = candidate.readerOverride
                        }
                    }
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CoverImportControls: View {
    @Binding var data: Data?
    @Binding var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $photo, matching: .images) { Label("Photos", systemImage: "photo") }
            Button { importing = true } label: { Label("Files", systemImage: "folder") }
            if loading { ProgressView("Preparing cover") }
            Text("Fit preview · up to 20 MB").font(.caption).foregroundStyle(MidokuTheme.secondaryText)
        }.disabled(loading)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            loading = true
            Task {
                defer { loading = false }
                do {
                    data = try await Task.detached {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        guard values.isRegularFile == true, let size = values.fileSize, size <= 20 * 1024 * 1024 else { throw LibraryFailure.cover }
                        return try Self.normalized(Data(contentsOf: url))
                    }.value
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
        .onChange(of: photo) {
            guard let selected = photo else { return }
            loading = true
            Task {
                defer { loading = false }
                do {
                    guard let bytes = try await selected.loadTransferable(type: Data.self) else { throw LibraryFailure.cover }
                    let normalized = try await Task.detached { try Self.normalized(bytes) }.value
                    guard photo == selected else { return }
                    data = normalized; error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    nonisolated static func normalized(_ bytes: Data) throws -> Data {
        guard bytes.count <= 20 * 1024 * 1024, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 80_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.75), data.count <= 1_048_576 else { throw LibraryFailure.cover }
        return data
    }
}

struct CategoryAssignmentView: View {
    let entryIDs: Set<UUID>
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<UUID> = []
    @State private var mode = "add"
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("Apply categories", selection: $mode) { Text("Add").tag("add"); Text("Remove").tag("remove"); Text("Replace all").tag("replace") }
                ForEach(settings.snapshot.categories) { category in
                    Toggle(category.name, isOn: Binding(get: { chosen.contains(category.id) }, set: { if $0 { chosen.insert(category.id) } else { chosen.remove(category.id) } }))
                }
                NavigationLink("Manage categories") { CategoriesSettingsView() }
                if let error { Text(error).foregroundStyle(MidokuTheme.danger) }
            }.settingsStyle().navigationTitle("Assign categories")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { Task { do {
                        let categories = chosen.intersection(settings.snapshot.categories.map(\.id))
                        try await settings.commit { state in for id in entryIDs { try state.library.editEntry(id) { entry in
                            if mode == "replace" { entry.categoryIDs = categories }
                            else if mode == "remove" { entry.categoryIDs.subtract(categories) }
                            else { entry.categoryIDs.formUnion(categories) }
                        } } }
                        dismiss()
                    } catch { self.error = error.localizedDescription } } } }.sharedBackgroundVisibility(.hidden)
                }
        }
    }
}

struct EntryReaderSettingsView: View {
    let entryID: UUID
    @Environment(AppSettingsStore.self) private var settings
    var body: some View {
        Form {
            Section {
                SettingPicker(title: "Reading mode", selection: binding(\.mode))
                SettingPicker(title: "Fit", selection: binding(\.fit))
                SettingPicker(title: "Background", selection: binding(\.background))
                SettingPicker(title: "Orientation", selection: binding(\.orientation))
                Toggle("Keep screen awake", isOn: binding(\.keepAwake))
                Toggle("Tap to navigate", isOn: binding(\.tapNavigation))
                SettingPicker(title: "Tap zones", selection: binding(\.tapZones))
            } footer: { Text("These preferences apply only to this library entry. Use Edit details to return to global defaults.") }
        }.settingsStyle().navigationTitle("Entry reader preferences")
    }
    private func binding<Value>(_ key: WritableKeyPath<ReaderPreferences, Value>) -> Binding<Value> {
        Binding(get: { (settings.snapshot.library.entry(entryID)?.readerOverride ?? settings.snapshot.preferences.reader)[keyPath: key] }, set: { value in
            settings.update { state in
                guard let index = state.library.entries.firstIndex(where: { $0.id == entryID }) else { return }
                var reader = state.library.entries[index].readerOverride ?? state.preferences.reader
                reader[keyPath: key] = value; state.library.entries[index].readerOverride = reader
            }
        })
    }
}
