import ColiUICore
import Foundation
import Observation

/// Terminal.dc.html: one `docker exec -it` session for a container.
/// Output is kept as a transcript so the terminal view can be rebuilt when the tab reopens.
@MainActor
@Observable
final class TerminalViewModel {
    enum State: Equatable {
        case idle, connecting, connected, ended
        case failed(String)
    }

    static let shells = ["/bin/sh", "/bin/bash", "/bin/zsh"]
    static let fontSizes: ClosedRange<CGFloat> = 9...24
    /// Enough for a long session without letting memory grow forever.
    static let transcriptLimit = 2_000_000

    var shell = "/bin/sh"
    var user = "root"
    private(set) var state: State = .idle
    private(set) var fontSize: CGFloat = 13
    private(set) var transcript = Data()

    let containerID: String
    private let connector: ShellConnector
    private var session: ShellSession?
    private var readTask: Task<Void, Never>?
    private var sink: ((Data) -> Void)?
    private var size = (columns: 80, rows: 24)
    /// Commands asked for before the shell connected; sent as soon as it does.
    private var queued: [String] = []

    init(containerID: String, connector: ShellConnector) {
        self.containerID = containerID
        self.connector = connector
    }

    /// The terminal view: receives the transcript so far, then every new chunk.
    func attach(_ sink: @escaping (Data) -> Void) {
        self.sink = sink
        if !transcript.isEmpty { sink(transcript) }
    }

    func detach() {
        sink = nil
    }

    func connect(columns: Int, rows: Int) async {
        guard state != .connecting, state != .connected else { return }
        size = (columns, rows)
        state = .connecting
        do {
            let session = try await connector.openShell(containerID: containerID, shell: shell, user: user, columns: columns, rows: rows)
            self.session = session
            state = .connected
            for command in queued { session.send(Data((command + "\n").utf8)) }
            queued = []
            readTask = Task { [weak self] in
                do {
                    for try await chunk in session.output { self?.receive(chunk) }
                    self?.sessionEnded(nil)
                } catch {
                    self?.sessionEnded(error.localizedDescription)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func receive(_ chunk: Data) {
        transcript.append(chunk)
        if transcript.count > Self.transcriptLimit {
            transcript.removeFirst(transcript.count - Self.transcriptLimit)
        }
        sink?(chunk)
    }

    private func sessionEnded(_ error: String?) {
        session = nil
        readTask = nil
        if state == .connected { state = error.map(State.failed) ?? .ended }
    }

    func send(_ data: Data) {
        session?.send(data)
    }

    /// Types a command and Return; waits for the connection if needed.
    func run(_ command: String) {
        if let session { session.send(Data((command + "\n").utf8)) } else { queued.append(command) }
    }

    func resize(columns: Int, rows: Int) {
        size = (columns, rows)
        session?.resize(columns: columns, rows: rows)
    }

    func disconnect() {
        let session = session
        self.session = nil
        readTask?.cancel()
        readTask = nil
        session?.close()
        if state == .connected || state == .connecting { state = .ended }
    }

    func newSession() async {
        disconnect()
        transcript = Data()
        sink?(Data("\u{1b}c".utf8)) // reset the emulator
        state = .idle
        await connect(columns: size.columns, rows: size.rows)
    }

    /// ⌘K: wipe screen and scrollback here, and let the shell redraw its prompt (Ctrl-L).
    func clear() {
        transcript = Data()
        sink?(Data("\u{1b}[H\u{1b}[2J\u{1b}[3J".utf8))
        session?.send(Data([0x0c]))
    }

    func biggerFont() { fontSize = min(fontSize + 1, Self.fontSizes.upperBound) }
    func smallerFont() { fontSize = max(fontSize - 1, Self.fontSizes.lowerBound) }

    /// The same session for Terminal.app: same socket, user and shell.
    func dockerCommand(socketPath: String) -> String {
        var parts = ["docker", "--host", "unix://\(socketPath)", "exec", "-it"]
        let user = user.trimmingCharacters(in: .whitespaces)
        if !user.isEmpty { parts += ["-u", user] }
        parts += [containerID, shell]
        return parts.map(Self.shellQuoted).joined(separator: " ")
    }

    /// Leaves plain words alone and single-quotes everything else.
    static func shellQuoted(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:@=-]+$"#, options: .regularExpression) != nil { return value }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
