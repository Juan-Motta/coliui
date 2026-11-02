import AppKit
import ColiUICore
import SwiftTerm
import SwiftUI

/// Terminal.dc.html: Shell / User pills, connection status, session buttons, the dark terminal panel and the footer.
struct TerminalSection: View {
    @Environment(AppModel.self) private var model
    let terminal: TerminalViewModel
    let container: Container?

    var body: some View {
        @Bindable var terminal = terminal
        let isRunning = container?.isRunning ?? false
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ToolbarPill(label: "Shell") {
                    Menu {
                        Picker("Shell", selection: $terminal.shell) {
                            ForEach(TerminalViewModel.shells, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(terminal.shell).font(.mono(12))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                .help("Shell to start; applies to the next session")

                ToolbarPill(label: "User") {
                    TextField("default", text: $terminal.user)
                        .textFieldStyle(.plain)
                        .font(.mono(12))
                        .frame(width: 56)
                }
                .help("User inside the container; empty uses the image's default. Applies to the next session")

                ConnectionStatus(state: terminal.state, isRunning: isRunning)

                Spacer()

                Button("Open in Terminal.app") { openInTerminalApp() }
                    .buttonStyle(TerminalPillStyle())
                    .disabled(!isRunning)
                    .help("Run the same docker exec in Terminal.app")
                Button("New session") { Task { await terminal.newSession() } }
                    .buttonStyle(TerminalPillStyle())
                    .disabled(!isRunning || terminal.state == .connecting)
                    .help("Close this shell and start another")
                Button("Disconnect") { terminal.disconnect() }
                    .buttonStyle(TerminalPillStyle(foreground: Palette.danger))
                    .disabled(terminal.state != .connected)
                    .help("End this shell")
            }

            ZStack {
                Palette.logBackground
                if isRunning {
                    TerminalPanel(terminal: terminal)
                        .padding(16)
                } else {
                    Text("Start \(container?.name ?? "the container") to open a shell.")
                        .font(.mono(13))
                        .foregroundStyle(Palette.logTime)
                }
            }
            .clipShape(.rect(cornerRadius: 14))
            .frame(maxHeight: .infinity)
            .background { TerminalShortcuts(terminal: terminal) }

            (Text("Runs ") + Text("docker exec -it").font(.mono(12)) + Text(" through the Engine API · ⌘K clears · ⌘+/⌘− font size"))
                .font(.ui(12))
                .foregroundStyle(Palette.secondary)
        }
    }

    /// Terminal.app asks once for permission to be controlled (System Settings › Privacy › Automation).
    private func openInTerminalApp() {
        let command = terminal.dockerCommand(socketPath: model.socketPath)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

/// `.pill`: 30 pt capsule on the field tint, 12 pt label, 6 pt gap.
private struct ToolbarPill<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            content
        }
        .font(.ui(12))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Palette.field, in: .capsule)
    }
}

private struct TerminalPillStyle: ButtonStyle {
    var foreground: SwiftUI.Color = Palette.text
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.ui(12))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(hovered && isEnabled ? Palette.fieldHover : Palette.field, in: .capsule)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .contentShape(.capsule)
        }
    }
}

private struct ConnectionStatus: View {
    let state: TerminalViewModel.State
    let isRunning: Bool

    var body: some View {
        let (title, color, dot): (String, SwiftUI.Color, SwiftUI.Color) = switch state {
        case _ where !isRunning: ("Container stopped", Palette.secondary, Palette.grayDot)
        case .connected: ("Connected", Palette.greenText, Palette.greenDot)
        case .connecting: ("Connecting…", Palette.secondary, Palette.grayDot)
        case .idle, .ended: ("Disconnected", Palette.secondary, Palette.grayDot)
        case .failed: ("Failed", Palette.danger, Palette.danger)
        }
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(title)
        }
        .font(.ui(12))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .help({ if case let .failed(message) = state { return message } else { return "" } }())
    }
}

/// ⌘K clears, ⌘+ / ⌘− change the font size.
private struct TerminalShortcuts: View {
    let terminal: TerminalViewModel

    var body: some View {
        Group {
            Button("Clear") { terminal.clear() }.keyboardShortcut("k")
            Button("Bigger") { terminal.biggerFont() }.keyboardShortcut("+")
            Button("Bigger") { terminal.biggerFont() }.keyboardShortcut("=")
            Button("Smaller") { terminal.smallerFont() }.keyboardShortcut("-")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// SwiftTerm's xterm emulator. The view model owns the session and transcript, so the tab can be rebuilt.
private struct TerminalPanel: NSViewRepresentable {
    let terminal: TerminalViewModel

    func makeCoordinator() -> Coordinator { Coordinator(terminal: terminal) }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = NSColor(Palette.logBackground)
        view.nativeForegroundColor = NSColor(Palette.logText)
        view.caretColor = NSColor(Palette.logText)
        view.font = NSFont.monospacedSystemFont(ofSize: terminal.fontSize, weight: .regular)
        view.optionAsMetaKey = true
        context.coordinator.view = view
        terminal.attach { [weak view] data in view?.feed(byteArray: ArraySlice([UInt8](data))) }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {
        if view.font.pointSize != terminal.fontSize {
            view.font = NSFont.monospacedSystemFont(ofSize: terminal.fontSize, weight: .regular)
        }
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.terminal.detach()
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        let terminal: TerminalViewModel
        weak var view: TerminalView?

        init(terminal: TerminalViewModel) {
            self.terminal = terminal
        }

        /// The first layout tells us the size, so that's when the session starts.
        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated {
                guard newCols > 0, newRows > 0 else { return }
                if terminal.state == .idle {
                    Task { await terminal.connect(columns: newCols, rows: newRows) }
                } else {
                    terminal.resize(columns: newCols, rows: newRows)
                }
            }
        }

        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Data(data)
            MainActor.assumeIsolated { terminal.send(bytes) }
        }

        nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { MainActor.assumeIsolated { _ = NSWorkspace.shared.open(url) } }
        }

        nonisolated func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            MainActor.assumeIsolated {
                Clipboard.copy(text)
            }
        }

        nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        nonisolated func scrolled(source: TerminalView, position: Double) {}
        nonisolated func bell(source: TerminalView) { MainActor.assumeIsolated { NSSound.beep() } }
        nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
