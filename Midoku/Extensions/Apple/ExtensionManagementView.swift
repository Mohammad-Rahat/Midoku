import SwiftUI

struct ExtensionManagementView: View {
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @State private var busy = false
    var body: some View {
        List {
            if let error = extensions.errorMessage {
                Section {
                    Text(error).foregroundStyle(MidokuTheme.secondaryText)
                    if !extensions.isReady { Button("Retry") { Task { await extensions.load() } } }
                }.listRowBackground(MidokuTheme.surface)
            }
            Section {
                ForEach(extensions.connections) { connection in
                    NavigationLink { SourceConnectionSettingsView(connectionID: connection.id, extensions: extensions) } label: {
                        SettingLabel(title: connection.name, symbol: "globe", detail: connection.isEnabled ? "Enabled" : "Disabled")
                    }
                }
                if extensions.connections.isEmpty { Text("Add a bundled source below to start browsing.").foregroundStyle(MidokuTheme.secondaryText) }
            } header: { Text("Your sources") } footer: {
                Text("Each connection has its own website session. Removing a connection keeps your pins, History, and reading positions.")
            }.listRowBackground(MidokuTheme.surface)
            Section {
                ForEach(extensions.available) { manifest in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(manifest.name).font(.headline)
                            Text("Version \(manifest.version)").font(.caption).foregroundStyle(MidokuTheme.secondaryText)
                        }
                        Spacer()
                        Button("Add") { Task { busy = true; await extensions.add(manifest); busy = false } }
                            .buttonStyle(.bordered).disabled(busy || !extensions.isReady)
                    }.padding(.vertical, 4)
                }
            } header: { Text("Bundled extensions") } footer: {
                Text("These reviewed extensions are included with Midoku. Updates arrive with app updates. Remote installation and automatic package updates are not available in this build.")
            }.listRowBackground(MidokuTheme.surface)
            let archived = settings.snapshot.connections.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Removed connections") {
                    ForEach(archived) { connection in
                        HStack {
                            Text(connection.name)
                            Spacer()
                            Button("Restore") { extensions.restoreConnection(connection) }
                                .disabled(!extensions.available.contains { $0.id == connection.extensionID })
                        }
                    }
                }.listRowBackground(MidokuTheme.surface)
            }
        }.settingsStyle().navigationTitle("Extensions")
    }
}

private struct SourceConnectionSettingsView: View {
    let connectionID: UUID
    let extensions: ExtensionEnvironment
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var rename = false
    @State private var remove = false
    @State private var signOut = false
    @State private var busy = false
    @State private var message: String?
    private var connection: SourceConnection? { settings.snapshot.connections.first { $0.id == connectionID } }
    private var manifest: ExtensionManifest? { extensions.available.first { $0.id == connection?.extensionID } }
    var body: some View {
        Form {
            if let connection {
                Section("Connection") {
                    Toggle("Enabled", isOn: Binding(get: { connection.isEnabled }, set: { value in
                        Task { await extensions.setEnabled(value, connectionID: connection.id) }
                    })).disabled(manifest == nil)
                    Button("Rename connection") { rename = true }
                    if let manifest {
                        LabeledContent("Extension", value: manifest.name)
                        LabeledContent("Version", value: manifest.version)
                        LabeledContent("Contract", value: "\(manifest.contractVersion)")
                    } else { Text("This extension is not bundled with the current app. Its saved references are kept.").font(.footnote) }
                }.listRowBackground(MidokuTheme.surface)
                Section {
                    Text("This extension does not declare account sign-in or additional source settings. Browse filters are available inside the source.")
                        .font(.footnote).foregroundStyle(MidokuTheme.secondaryText)
                    Button("Clear website session", role: .destructive) { signOut = true }.disabled(busy)
                } header: { Text("Website session") } footer: {
                    Text("Clearing this connection's session removes its website cookies and verification state. Other sources, pins, and reading data are kept.")
                }.listRowBackground(MidokuTheme.surface)
                if let manifest {
                    Section("Allowed domains") { ForEach(manifest.domains, id: \.self) { Text($0).font(.footnote).textSelection(.enabled) } }
                        .listRowBackground(MidokuTheme.surface)
                    Section("Capabilities") {
                        Text(manifest.capabilities.map(\.rawValue).sorted().joined(separator: ", ")).font(.footnote)
                    }.listRowBackground(MidokuTheme.surface)
                }
                Section { Button("Remove connection", role: .destructive) { remove = true } }.listRowBackground(MidokuTheme.surface)
                if let message { Text(message).font(.footnote).listRowBackground(MidokuTheme.surface) }
            }
        }.settingsStyle().navigationTitle(connection?.name ?? "Source")
            .sheet(isPresented: $rename) {
                if let connection {
                    NameEditor(title: "Rename connection", name: connection.name, limit: 100) { extensions.rename(connection, name: $0) }
                }
            }
            .confirmationDialog("Remove source connection?", isPresented: $remove, titleVisibility: .visible) {
                Button("Remove connection", role: .destructive) {
                    guard let connection else { return }
                    Task { await extensions.archive(connection); dismiss() }
                }
            } message: { Text("Browsing is disabled. Your Home sections, reading positions, and History are retained. You can restore this same connection later.") }
            .confirmationDialog("Clear website session?", isPresented: $signOut, titleVisibility: .visible) {
                Button("Clear session", role: .destructive) {
                    Task {
                        busy = true
                        await extensions.browserSessions.clearSession(for: connectionID)
                        await extensions.images.clear()
                        busy = false; message = "Website session cleared."
                    }
                }
            } message: { Text("This may require website verification again. No reading data will be removed.") }
    }
}
