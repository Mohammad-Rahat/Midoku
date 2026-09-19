import SwiftUI

struct SourceFilterSheet: View {
    let scope: SourceSearchFilter.Scope
    let load: () async throws -> [SourceSearchFilter]
    let apply: (SourceFilterValues) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SourceFilterValues
    @State private var definitions: [SourceSearchFilter] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var retry = 0

    init(values: SourceFilterValues, scope: SourceSearchFilter.Scope,
         load: @escaping () async throws -> [SourceSearchFilter],
         apply: @escaping (SourceFilterValues) -> Void) {
        self.scope = scope
        self.load = load
        self.apply = apply
        _draft = State(initialValue: values)
    }

    private var canApply: Bool {
        !isLoading && errorMessage == nil && definitions.allSatisfy {
            !$0.required || !(draft[$0.id] ?? $0.defaults).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading { ProgressView("Loading filters") }
                if let errorMessage { SourceErrorView(message: errorMessage) { retry += 1 } }
                ForEach(definitions) { filter in
                    if filter.kind == .single {
                        Picker(filter.title, selection: singleSelection(filter)) {
                            if !filter.required { Text("Any").tag("") }
                            ForEach(filter.options) { option in Text(option.title).tag(option.id) }
                        }
                    } else {
                        NavigationLink {
                            SourceFilterOptions(filter: filter, selection: multipleSelection(filter))
                        } label: {
                            LabeledContent(filter.title, value: summary(filter))
                        }
                    }
                }
                if !isLoading, errorMessage == nil {
                    Section {
                        Button("Reset filters") { draft = [:] }
                    } footer: {
                        Text("Changes apply when you tap Apply. Feed tabs keep their own ordering.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MidokuTheme.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        for filter in definitions where Set(draft[filter.id] ?? filter.defaults) == Set(filter.defaults) {
                            draft.removeValue(forKey: filter.id)
                        }
                        apply(draft)
                        dismiss()
                    }
                    .disabled(!canApply)
                }.sharedBackgroundVisibility(.hidden)
            }
            .task(id: retry) {
                isLoading = true
                do {
                    definitions = try await load().filter { $0.scopes.contains(scope) }
                    errorMessage = nil
                } catch {
                    if !Task.isCancelled { errorMessage = error.localizedDescription }
                }
                isLoading = false
            }
        }
    }

    private func singleSelection(_ filter: SourceSearchFilter) -> Binding<String> {
        Binding {
            (draft[filter.id] ?? filter.defaults).first ?? ""
        } set: { draft[filter.id] = $0.isEmpty ? [] : [$0] }
    }

    private func multipleSelection(_ filter: SourceSearchFilter) -> Binding<[String]> {
        Binding { draft[filter.id] ?? filter.defaults } set: { draft[filter.id] = $0 }
    }

    private func summary(_ filter: SourceSearchFilter) -> String {
        let ids = draft[filter.id] ?? filter.defaults
        if ids.isEmpty { return "Any" }
        return filter.options.filter { ids.contains($0.id) }.map(\.title).formatted(.list(type: .and))
    }
}

private struct SourceFilterOptions: View {
    let filter: SourceSearchFilter
    @Binding var selection: [String]
    @State private var query = ""

    private var options: [SourceFilterOption] {
        query.isEmpty ? filter.options : filter.options.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if filter.required, selection.isEmpty {
                Text("Select at least one option.").foregroundStyle(MidokuTheme.secondaryText)
            }
            ForEach(options) { option in
                Button {
                    if selection.contains(option.id) { selection.removeAll { $0 == option.id } }
                    else { selection.append(option.id) }
                } label: {
                    HStack {
                        Text(option.title).foregroundStyle(MidokuTheme.primaryText)
                        Spacer()
                        if selection.contains(option.id) { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 32).contentShape(Rectangle())
                }
                .accessibilityAddTraits(selection.contains(option.id) ? .isSelected : [])
            }
        }
        .scrollContentBackground(.hidden).background(MidokuTheme.background)
        .navigationTitle(filter.title)
        .searchable(text: $query, prompt: "Find an option")
        .toolbar {
            Button("Clear") { selection = [] }
        }
    }
}
