import Darwin
import Foundation
import Testing
@testable import ColiUICore

/// A Unix socket server that answers each connection with `reply`, then keeps it open or closes it.
private final class ReplyServer: @unchecked Sendable {
    let path: String
    private let fd: Int32

    init(reply: Data, keepOpen: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString.prefix(8).description)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("s.sock").path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strncpy($0, path, 103) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw DockerError.connectionFailed("test server") }
        let fd = fd
        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = read(client, &buffer, buffer.count)
                _ = reply.withUnsafeBytes { write(client, $0.baseAddress, reply.count) }
                if !keepOpen { close(client) }
            }
        }
    }

    func stop() {
        shutdown(fd, SHUT_RDWR)
        close(fd)
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }
}

private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@Suite struct StreamingSocketTests {
    @Test func readsUntilTheEngineCloses() throws {
        let server = try ReplyServer(reply: Data("hello".utf8), keepOpen: false)
        defer { server.stop() }
        var received = Data()
        try StreamingSocket().run(socketPath: server.path, request: Data("GET / HTTP/1.1\r\n\r\n".utf8)) { received.append($0) }
        #expect(received == Data("hello".utf8))
    }

    /// The old adapters closed the socket and then let `onTermination` shut down that number again,
    /// which by then could belong to another connection (the shell, a stats request).
    @Test func aCancelAfterTheStreamEndedLeavesOtherSocketsAlone() throws {
        let server = try ReplyServer(reply: Data("boom".utf8), keepOpen: true)
        defer { server.stop() }
        let stream = StreamingSocket()
        #expect(throws: DockerError.malformedResponse) {
            try stream.run(socketPath: server.path, request: Data("GET / HTTP/1.1\r\n\r\n".utf8)) { _ in throw DockerError.malformedResponse }
        }

        // A new connection takes the lowest free descriptor: very likely the one just closed.
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        stream.cancel()

        #expect(write(pair[0], "x", 1) == 1)
        var byte: UInt8 = 0
        #expect(read(pair[1], &byte, 1) == 1)
    }

    @Test func cancelEndsABlockedRead() async throws {
        let server = try ReplyServer(reply: Data("first".utf8), keepOpen: true)
        defer { server.stop() }
        let stream = StreamingSocket()
        let done = Box(false)
        let chunks = Box(0)
        Thread.detachNewThread {
            try? stream.run(socketPath: server.path, request: Data("GET / HTTP/1.1\r\n\r\n".utf8)) { _ in chunks.value += 1 }
            done.value = true
        }
        for _ in 0..<100 where chunks.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        stream.cancel()
        for _ in 0..<100 where !done.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done.value)
    }

    @Test func cancellingBeforeTheConnectionNeverReads() throws {
        let server = try ReplyServer(reply: Data("late".utf8), keepOpen: true)
        defer { server.stop() }
        let stream = StreamingSocket()
        stream.cancel()
        var received = Data()
        try stream.run(socketPath: server.path, request: Data("GET / HTTP/1.1\r\n\r\n".utf8)) { received.append($0) }
        #expect(received.isEmpty)
    }
}
