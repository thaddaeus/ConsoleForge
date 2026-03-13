import SwiftUI

struct SessionEditorView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var session: SessionConfiguration

    private let models = ["", "opus", "sonnet", "haiku"]
    private let efforts = ["", "low", "medium", "high", "max"]
    private let iconOptions = [
        "terminal", "bolt", "cpu", "server.rack",
        "hammer", "wrench.and.screwdriver", "ant", "ladybug",
        "text.page", "doc.text", "globe", "network"
    ]
    private let colorPresets = [
        "#007AFF", "#FF2D55", "#5856D6", "#FF9500",
        "#34C759", "#AF52DE", "#00C7BE", "#FF6482"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("General") {
                    TextField("Name", text: $session.name)

                    HStack {
                        TextField("Working Directory", text: $session.workingDirectory)
                        Button("Browse...") {
                            selectDirectory()
                        }
                    }

                    Toggle("Auto-start on launch", isOn: $session.autoStart)
                    Toggle("Continue previous session", isOn: $session.continueSession)
                }

                Section("Claude Settings") {
                    Picker("Model", selection: Binding(
                        get: { session.model ?? "" },
                        set: { session.model = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Default").tag("")
                        ForEach(models.dropFirst(), id: \.self) { model in
                            Text(model.capitalized).tag(model)
                        }
                    }

                    Picker("Permission Mode", selection: Binding(
                        get: { session.permissionMode ?? .default },
                        set: { session.permissionMode = $0 }
                    )) {
                        ForEach(SessionConfiguration.PermissionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("Effort", selection: Binding(
                        get: { session.effortLevel ?? "" },
                        set: { session.effortLevel = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Default").tag("")
                        ForEach(efforts.dropFirst(), id: \.self) { level in
                            Text(level.capitalized).tag(level)
                        }
                    }
                }

                Section("Prompts") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { session.systemPrompt ?? "" },
                            set: { session.systemPrompt = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Append System Prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { session.appendSystemPrompt ?? "" },
                            set: { session.appendSystemPrompt = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Initial Prompt (sent on launch)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { session.initialPrompt ?? "" },
                            set: { session.initialPrompt = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                    }
                }

                Section("Advanced") {
                    TextField("MCP Config Path", text: Binding(
                        get: { session.mcpConfigPath ?? "" },
                        set: { session.mcpConfigPath = $0.isEmpty ? nil : $0 }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Additional Flags (one per line)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $session.additionalFlags)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60)
                    }
                }

                Section("Appearance") {
                    // Tab Color
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tab Color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(colorPresets, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex) ?? .blue)
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if session.tabColorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture {
                                        session.tabColorHex = hex
                                    }
                            }
                        }
                    }

                    // Tab Icon
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tab Icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(session.tabIconName == icon ? Color.accentColor.opacity(0.2) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture {
                                        session.tabIconName = icon
                                    }
                            }
                        }
                    }

                    // Move to folder
                    Picker("Folder", selection: Binding(
                        get: { session.folderID ?? store.folders.first?.id ?? UUID() },
                        set: { session.folderID = $0 }
                    )) {
                        ForEach(store.folders) { folder in
                            Text(folder.name).tag(folder.id)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Save & Launch") {
                    saveAndLaunch()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Spacer()
            }
            .padding()
        }
        .frame(width: 520, height: 700)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let expanded = try? URL(fileURLWithPath: (session.workingDirectory as NSString).expandingTildeInPath) {
            panel.directoryURL = expanded
        }
        if panel.runModal() == .OK, let url = panel.url {
            session.workingDirectory = url.path
        }
    }

    private func saveAndDismiss() {
        store.updateSession(session)
        dismiss()
    }

    private func saveAndLaunch() {
        store.updateSession(session)
        store.openTab(sessionID: session.id)
        dismiss()
    }
}
