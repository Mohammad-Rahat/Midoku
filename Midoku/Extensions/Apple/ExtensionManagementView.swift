import SwiftUI

struct ExtensionManagementView: View {
    let extensions: ExtensionEnvironment
    @State private var isSaving = false

    var body: some View {
        List {
            if let error = extensions.errorMessage {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    if !extensions.isReady {
                        Button("Retry") { Task { await extensions.load() } }
                    }
                }
            }
            if extensions.connections.isEmpty && extensions.available.isEmpty {
                ContentUnavailableView {
                    Image(decorative: "MidokuExtensionPlaceholder")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                    Text("No extensions yet")
                        .foregroundStyle(MidokuTheme.primaryText)
                } description: {
                    Text("Your manga sources will appear here once added.")
                        .foregroundStyle(MidokuTheme.secondaryText)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if !extensions.connections.isEmpty {
                Section("Your sources") {
                    ForEach(extensions.connections) { connection in
                        Toggle(connection.name, isOn: Binding(
                            get: { connection.isEnabled },
                            set: { enabled in
                                isSaving = true
                                Task {
                                    await extensions.setEnabled(enabled, connectionID: connection.id)
                                    isSaving = false
                                }
                            }
                        ))
                        .disabled(isSaving)
                    }
                }
            }
            if !extensions.available.isEmpty {
                Section("Available extensions") {
                    ForEach(extensions.available) { manifest in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(manifest.name)
                                Text(manifest.version).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                isSaving = true
                                Task {
                                    await extensions.add(manifest)
                                    isSaving = false
                                }
                            }
                            .disabled(isSaving || !extensions.isReady)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MidokuTheme.background)
        .navigationTitle("Extensions")
    }
}
