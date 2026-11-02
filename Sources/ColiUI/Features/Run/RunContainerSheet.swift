import AppKit
import ColiUICore
import SwiftUI
import UniformTypeIdentifiers

/// RunContainer.dc.html: "Run a new container" sheet (640 pt, 24/26 pt padding, 16 pt rhythm).
struct RunContainerSheet: View {
    @Environment(AppModel.self) private var model
    let form: RunContainerViewModel

    var body: some View {
        @Bindable var form = form
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Run a new container").font(.ui(17, .semibold))

                HStack(alignment: .top, spacing: 12) {
                    labeled("Image") { FormField(text: $form.image, placeholder: "postgres:16-alpine", mono: true) }
                    labeled("Name (optional)") { FormField(text: $form.name, placeholder: "postgres-test") }
                }

                section("Ports") {
                    ForEach($form.ports) { $row in
                        HStack(spacing: 8) {
                            FormField(text: $row.host, placeholder: "5433", mono: true).frame(width: 90)
                                .accessibilityLabel("Host port")
                            Text("→").foregroundStyle(Palette.secondary)
                            FormField(text: $row.container, placeholder: "5432", mono: true).frame(width: 90)
                                .accessibilityLabel("Container port")
                            Picker("Protocol", selection: $row.proto) {
                                Text("tcp").tag("tcp")
                                Text("udp").tag("udp")
                            }
                            .labelsHidden()
                            .frame(width: 76)
                            removeButton("Remove port") { form.ports.removeAll { $0.id == row.id } }
                        }
                    }
                    addButton("+ Add port") { form.ports.append(PortRow()) }
                }

                section("Volumes") {
                    ForEach($form.volumes) { $row in
                        HStack(spacing: 8) {
                            FormField(text: $row.source, placeholder: "pgdata or ~/code/app", mono: true)
                                .accessibilityLabel("Host path or volume")
                            Text("→").foregroundStyle(Palette.secondary)
                            FormField(text: $row.target, placeholder: "/var/lib/postgresql/data", mono: true)
                                .frame(minWidth: 200)
                                .accessibilityLabel("Container path")
                            Button { chooseFolder(for: row.id) } label: {
                                Label { Text("Choose folder") } icon: { LineIcon(kind: .folder).icon(Palette.secondary, size: 15) }
                            }
                            .buttonStyle(ToolbarIconButtonStyle(width: 30))
                            .help("Choose a folder on your Mac")
                        }
                    }
                    addButton("+ Add volume") { form.volumes.append(VolumeRow()) }
                }

                section("Environment") {
                    ForEach($form.environment) { $row in
                        HStack(spacing: 8) {
                            FormField(text: $row.key, placeholder: "POSTGRES_PASSWORD", mono: true)
                                .accessibilityLabel("Variable name")
                            Text("=").foregroundStyle(Palette.secondary)
                            FormField(
                                text: $row.value,
                                placeholder: "value",
                                mono: true,
                                secure: EnvironmentVariable(key: row.key, value: "").isSecret
                            )
                            .accessibilityLabel("Variable value")
                            removeButton("Remove variable") { form.environment.removeAll { $0.id == row.id } }
                        }
                    }
                    HStack(spacing: 4) {
                        addButton("+ Add variable") { form.environment.append(EnvRow()) }
                        Text("·").foregroundStyle(Palette.secondary).font(.ui(12))
                        addButton("Import .env file…", action: importEnv)
                    }
                }

                FlowLayout(spacing: 20, lineSpacing: 8) {
                    HStack(spacing: 8) {
                        Text("Restart").font(.ui(13))
                        Picker("Restart", selection: $form.restartPolicy) {
                            ForEach(RestartPolicy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle("Remove when stopped (--rm)", isOn: $form.autoRemove).toggleStyle(.checkbox).font(.ui(13))
                    Toggle("Pull latest image", isOn: $form.pull).toggleStyle(.checkbox).font(.ui(13))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Equivalent command").font(.ui(12, .semibold)).foregroundStyle(Palette.tertiary)
                        Spacer()
                        addButton("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(form.commandToCopy, forType: .string)
                        }
                        .help("Copy the command with real values")
                    }
                    Text(highlighted(form.commandPreview))
                        .font(.mono(12))
                        .lineSpacing(7)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Palette.logBackground, in: .rect(cornerRadius: 14))
                }

                if let message = form.showValidation ? (form.validationError ?? form.errorMessage) : form.errorMessage {
                    Text(message).font(.ui(12)).foregroundStyle(Palette.danger)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { model.closeRunForm() }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button {
                        Task { await model.submitRunForm() }
                    } label: {
                        HStack(spacing: 6) {
                            if form.isRunning { ProgressView().controlSize(.mini).tint(.white) }
                            Text(form.isRunning ? (form.pull ? "Pulling…" : "Starting…") : "Run")
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(TintButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.isRunning)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .frame(width: 640)
        .frame(minHeight: 560, idealHeight: 760)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.ui(12)).foregroundStyle(Palette.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.ui(12, .semibold)).foregroundStyle(Palette.tertiary).padding(.bottom, 2)
            content()
        }
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Hoverable { hovered in
                Text(title).font(.ui(12)).foregroundStyle(Palette.accent).underline(hovered)
            }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(label) } icon: { LineIcon(kind: .minus).icon(Palette.secondary, size: 14, svgStrokeWidth: 2.2) }
        }
        .buttonStyle(ToolbarIconButtonStyle(width: 30))
        .help(label)
    }

    /// "docker run" in cyan and the image (last line) in yellow, like the design.
    private func highlighted(_ command: String) -> AttributedString {
        var text = AttributedString(command)
        text.foregroundColor = Palette.logText
        if let range = text.range(of: "docker run") { text[range].foregroundColor = Palette.logInfo }
        if let lastLine = command.split(separator: "\n").last,
           let range = text.range(of: lastLine.trimmingCharacters(in: .whitespaces), options: .backwards) {
            text[range].foregroundColor = Palette.logWarn
        }
        return text
    }

    private func chooseFolder(for id: VolumeRow.ID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let index = form.volumes.firstIndex(where: { $0.id == id }) else { return }
        let home = NSHomeDirectory()
        form.volumes[index].source = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func importEnv() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        form.importEnv(text)
    }
}

/// `.in`: 30 pt field, 10 pt radius, soft fill.
private struct FormField: View {
    @Binding var text: String
    let placeholder: String
    var mono = false
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(mono ? .mono(12) : .ui(13))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Palette.field, in: .rect(cornerRadius: 10))
    }
}
