import SwiftUI

struct AddToLibrarySheet: View {
    let title: String
    let source: String
    let language: String?
    let save: (LibraryAddOptions) async throws -> Void
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var options = LibraryAddOptions()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text([source, language?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                    }.padding(.vertical, 4)
                }.listRowBackground(MidokuTheme.surface)
                Section("Reading") {
                    Picker("Status", selection: $options.status) {
                        ForEach(PersonalStatus.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Follow new chapters", isOn: $options.followsNewChapters)
                }.listRowBackground(MidokuTheme.surface)
                Section("Categories") {
                    ForEach(settings.snapshot.categories) { category in
                        Button {
                            if !options.categoryIDs.insert(category.id).inserted { options.categoryIDs.remove(category.id) }
                        } label: {
                            HStack {
                                Text(category.name).foregroundStyle(MidokuTheme.primaryText)
                                Spacer()
                                Image(systemName: options.categoryIDs.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(.tint)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(options.categoryIDs.contains(category.id) ? .isSelected : [])
                    }
                    NavigationLink { CategoriesSettingsView() } label: { Label("Manage categories", systemImage: "folder.badge.plus") }
                }.listRowBackground(MidokuTheme.surface)
                if let error { Text(error).font(.callout).foregroundStyle(MidokuTheme.danger) }
            }.settingsStyle().navigationTitle("Add to library")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Adding…" : "Add") {
                            saving = true; error = nil
                            Task {
                                defer { saving = false }
                                do { try await save(options); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(saving)
                    }
                }
                .disabled(saving)
        }.interactiveDismissDisabled(saving)
    }
}
