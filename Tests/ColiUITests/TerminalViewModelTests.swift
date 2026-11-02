import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeShellSession: ShellSession, @unchecked Sendable {
    let output: AsyncThrowingStream<Data, Error>
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var _sent: [Data] = []
    private var _sizes: [String] = []
    private var _closed = false

    init() {
        (output, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    }

    var sent: [Data] { lock.withLock { _sent } }
    var sizes: [String] { lock.withLock { _sizes } }
    var closed: Bool { lock.withLock { _closed } }

    func send(_ data: Data) { lock.withLock { _sent.append(data) } }
    func resize(columns: Int, rows: Int) { lock.withLock { _sizes.append("\(columns)x\(rows)") } }
    func close() {
        lock.withLock { _closed = true }
        continuation.finish()
    }
}

final class FakeShellConnector: ShellConnector, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [String] = []
    private var _sessions: [FakeShellSession] = []
    var error: Error?

    var opened: [String] { lock.withLock { _opened } }
    var sessions: [FakeShellSession] { lock.withLock { _sessions } }

    func openShell(containerID: String, shell: String, user: String, columns: Int, rows: Int) async throws -> ShellSession {
        lock.withLock { _opened.append("\(containerID) \(shell) \(user) \(columns)x\(rows)") }
        if let error { throw error }
        let session = FakeShellSession()
        lock.withLock { _sessions.append(session) }
        return session
    }
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1_000 where !condition() { await Task.yield() }
}

@MainActor
@Suite struct TerminalViewModelTests {
    @Test func defaultsFollowTheDesign() {
        let model = TerminalViewModel(containerID: "c1", connector: FakeShellConnector())
        #expect(model.shell == "/bin/sh")
        #expect(model.user == "root")
        #expect(model.fontSize == 13)
        #expect(model.state == .idle)
    }

    @Test func connectsAndStreamsOutputToTheView() async {
        let connector = FakeShellConnector()
        let model = TerminalViewModel(containerID: "c1", connector: connector)
        model.shell = "/bin/bash"
        await model.connect(columns: 120, rows: 40)

        #expect(connector.opened == ["c1 /bin/bash root 120x40"])
        #expect(model.state == .connected)
        connector.sessions[0].continuation.yield(Data("root@c1:/# ".utf8))
        await waitUntil { !model.transcript.isEmpty }

        var shown = Data()
        model.attach { shown.append($0) }
        #expect(String(decoding: shown, as: UTF8.self) == "root@c1:/# ")
        connector.sessions[0].continuation.yield(Data("ls\r\n".utf8))
        await waitUntil { shown.count > 11 }
        #expect(String(decoding: shown, as: UTF8.self) == "root@c1:/# ls\r\n")
    }

    @Test func forwardsKeysAndSizes() async {
        let connector = FakeShellConnector()
        let model = TerminalViewModel(containerID: "c1", connector: connector)
        await model.connect(columns: 80, rows: 24)
        model.send(Data("ls\r".utf8))
        model.resize(columns: 100, rows: 30)
        #expect(connector.sessions[0].sent == [Data("ls\r".utf8)])
        #expect(connector.sessions[0].sizes == ["100x30"])
    }

    @Test func shellExitEndsTheSession() async {
        let connector = FakeShellConnector()
        let model = TerminalViewModel(containerID: "c1", connector: connector)
        await model.connect(columns: 80, rows: 24)
        connector.sessions[0].continuation.finish()
        await waitUntil { model.state != .connected }
        #expect(model.state == .ended)
    }

    @Test func connectionFailuresAreShown() async {
        let connector = FakeShellConnector()
        connector.error = DockerError.requestFailed(status: 409, message: "container e81b is not running")
        let model = TerminalViewModel(containerID: "c1", connector: connector)
        await model.connect(columns: 80, rows: 24)
        #expect(model.state == .failed("container e81b is not running"))
    }

    @Test func disconnectAndNewSession() async {
        let connector = FakeShellConnector()
        let model = TerminalViewModel(containerID: "c1", connector: connector)
        await model.connect(columns: 80, rows: 24)
        model.disconnect()
        #expect(connector.sessions[0].closed)
        #expect(model.state == .ended)

        await model.newSession()
        #expect(connector.opened.count == 2)
        #expect(connector.opened.last == "c1 /bin/sh root 80x24")
        #expect(model.state == .connected)
        #expect(model.transcript.isEmpty)
    }

    @Test func clearAsksTheShellToRedraw() async {
        let connector = FakeShellConnector()
        let model = TerminalViewModel(containerID: "c1", connector: connector)
        await model.connect(columns: 80, rows: 24)
        var shown = Data()
        model.attach { shown.append($0) }
        model.clear()
        #expect(String(decoding: shown, as: UTF8.self) == "\u{1b}[H\u{1b}[2J\u{1b}[3J")
        #expect(connector.sessions[0].sent == [Data([0x0c])])
    }

    @Test func fontSizeStaysReadable() {
        let model = TerminalViewModel(containerID: "c1", connector: FakeShellConnector())
        for _ in 0..<20 { model.biggerFont() }
        #expect(model.fontSize == 24)
        for _ in 0..<30 { model.smallerFont() }
        #expect(model.fontSize == 9)
    }

    @Test func terminalAppCommandUsesTheSameSocketAndOptions() {
        let model = TerminalViewModel(containerID: "e81b3f0c55d2", connector: FakeShellConnector())
        model.shell = "/bin/bash"
        #expect(model.dockerCommand(socketPath: "/Users/me/.colima/default/docker.sock")
                == "docker --host unix:///Users/me/.colima/default/docker.sock exec -it -u root e81b3f0c55d2 /bin/bash")
        model.user = ""
        #expect(model.dockerCommand(socketPath: "/s.sock") == "docker --host unix:///s.sock exec -it e81b3f0c55d2 /bin/bash")
        // The user field is free text and ends up in a shell: anything unusual is single-quoted.
        model.user = "a b; rm -rf ~"
        #expect(model.dockerCommand(socketPath: "/My Socket's.sock")
                == "docker --host 'unix:///My Socket'\\''s.sock' exec -it -u 'a b; rm -rf ~' e81b3f0c55d2 /bin/bash")
    }
}
