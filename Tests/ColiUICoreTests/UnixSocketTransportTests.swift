import Darwin
import Foundation
import Testing
@testable import ColiUICore

@Suite struct UnixSocketTransportTests {
    /// Stats calls hold their socket for about a second. While they wait, other async work (the terminal's
    /// output, the UI's tasks) must keep running instead of queueing behind them for a free thread.
    @Test func waitingRequestsLeaveTheConcurrencyPoolFree() async throws {
        let server = try SlowServer(delay: 1)
        defer { server.stop() }
        let transport = UnixSocketTransport(socketPath: server.path)

        let count = ProcessInfo.processInfo.activeProcessorCount * 2
        let requests = (0..<count).map { _ in
            Task.detached(priority: .userInitiated) {
                try await transport.send(method: "GET", path: "/containers/c1/stats?stream=false", body: nil)
            }
        }
        try await Task.sleep(for: .milliseconds(200))

        let start = ContinuousClock.now
        _ = await Task.detached(priority: .userInitiated) { 1 }.value
        #expect(ContinuousClock.now - start < .milliseconds(300))

        for request in requests {
            #expect(try await request.value.statusCode == 200)
        }
    }
}

/// A Unix socket server that answers every request with `{}` after `delay` seconds.
private final class SlowServer: @unchecked Sendable {
    let path: String
    private let fd: Int32

    init(delay: UInt32) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString.prefix(8).description)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("s.sock").path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        // The server replies even to clients that already left (the cancel tests). Accepted Unix sockets don't
        // inherit SO_NOSIGPIPE and can't take it once the peer closed, so ignore SIGPIPE in the test process.
        signal(SIGPIPE, SIG_IGN)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strncpy($0, path, 103) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 64) == 0 else { throw DockerError.connectionFailed("test server") }
        let listener = fd
        Thread.detachNewThread {
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                Thread.detachNewThread {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    _ = read(client, &buffer, buffer.count)
                    sleep(delay)
                    let reply = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
                    _ = reply.withCString { write(client, $0, strlen($0)) }
                    close(client)
                }
            }
        }
    }

    func stop() {
        shutdown(fd, SHUT_RDWR)
        close(fd)
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }
}

@Suite struct UnixSocketConnectErrorTests {
    /// The system's reason says why Docker couldn't be reached (missing socket, refused, …).
    @Test func connectionErrorsCarryTheSystemReason() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("coliui-missing.sock").path
        do {
            _ = try await UnixSocketTransport(socketPath: path).send(method: "GET", path: "/_ping", body: nil)
            Issue.record("expected a connection error")
        } catch {
            #expect(error as? DockerError == .socketUnavailable(path: path, reason: "No such file or directory"))
            #expect(error.localizedDescription == "Docker isn't reachable at \(path) (No such file or directory). Is Colima running?")
        }
    }
}
