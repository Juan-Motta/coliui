import Darwin
import Foundation

extension DockerEngineRepository {
    /// `docker exec -it`: a TTY exec with stdin; an empty user keeps the image's default.
    func createExec(containerID: String, shell: String, user: String, columns: Int, rows: Int) async throws -> String {
        let id = try Self.validated(containerID)
        var payload: [String: Any] = [
            "AttachStdin": true, "AttachStdout": true, "AttachStderr": true, "Tty": true,
            "Cmd": [shell], "Env": ["TERM=xterm-256color"], "ConsoleSize": [rows, columns],
        ]
        let user = user.trimmingCharacters(in: .whitespaces)
        if !user.isEmpty { payload["User"] = user }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return try await decode(ExecCreatedDTO.self, method: "POST", path: "/containers/\(id)/exec", body: body).id
    }

    func resizeExec(id: String, columns: Int, rows: Int) async throws {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "POST", path: "/exec/\(id)/resize?h=\(rows)&w=\(columns)", body: nil)
        try Self.check(response)
    }
}

private struct ExecCreatedDTO: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

/// `ShellConnector` over the Colima socket: creates the exec, then hijacks `/exec/{id}/start`
/// so the connection becomes a raw two-way TTY stream.
public struct DockerShell: ShellConnector {
    private let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func openShell(containerID: String, shell: String, user: String, columns: Int, rows: Int) async throws -> ShellSession {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socketPath))
        let execID = try await repository.createExec(containerID: containerID, shell: shell, user: user, columns: columns, rows: rows)
        let socketPath = socketPath
        let (fd, leftover) = try await BlockingIO.run {
            let fd = try UnixSocketTransport.connect(socketPath: socketPath, timeoutSeconds: 0)
            do {
                try UnixSocketTransport.writeAll(Self.startRequest(execID: execID), to: fd)
                var head = Data()
                var chunk = [UInt8](repeating: 0, count: 16 * 1024)
                while true {
                    let count = read(fd, &chunk, chunk.count)
                    if count > 0 {
                        head.append(chunk, count: count)
                        if let rest = try Self.upgrade(head) { return (fd, rest) }
                    } else if count == 0 {
                        throw DockerError.connectionFailed("Docker closed the shell before it started.")
                    } else if errno != EINTR {
                        throw DockerError.connectionFailed(String(cString: strerror(errno)))
                    }
                }
            } catch {
                close(fd)
                throw error
            }
        }
        return DockerShellSession(fd: fd, leftover: leftover, execID: execID, repository: repository)
    }

    static func startRequest(execID: String) -> Data {
        let body = #"{"Detach":false,"Tty":true}"#
        var head = "POST /exec/\(execID)/start HTTP/1.1\r\n"
        head += "Host: localhost\r\n"
        head += "User-Agent: ColiUI\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Connection: Upgrade\r\n"
        head += "Upgrade: tcp\r\n"
        head += "Content-Length: \(body.utf8.count)\r\n\r\n"
        return Data((head + body).utf8)
    }

    /// The bytes after the response head once the engine accepted the upgrade; nil while the head is incomplete.
    static func upgrade(_ raw: Data) throws -> Data? {
        guard let end = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let statusLine = String(decoding: raw[raw.startIndex..<end.lowerBound], as: UTF8.self).prefix { $0 != "\r" }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else { throw DockerError.malformedResponse }
        let rest = Data(raw[end.upperBound...])
        guard status == 101 || status == 200 else {
            try DockerEngineRepository.check(HTTPResponse(statusCode: status, headers: [:], body: rest))
            throw DockerError.malformedResponse
        }
        return rest
    }
}

/// One live shell. Output arrives on `output`; closing shuts the socket, which ends the stream.
/// Writes can block forever (the socket has no timeout and a program may never read stdin), so they
/// never hold `lock`: `close()` must always be able to shut the socket down, which also fails the write.
/// Only the reader closes the descriptor, after the write queue drains, so no write can hit a reused fd.
final class DockerShellSession: ShellSession, @unchecked Sendable {
    let output: AsyncThrowingStream<Data, Error>
    private let fd: Int32
    private let execID: String
    private let repository: DockerEngineRepository
    private let writer = DispatchQueue(label: "ColiUI.shell.writer")
    private let lock = NSLock()
    private var finished = false
    private var lastResize: Task<Void, Never>?

    init(fd: Int32, leftover: Data, execID: String, repository: DockerEngineRepository) {
        self.fd = fd
        self.execID = execID
        self.repository = repository
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        output = stream
        if !leftover.isEmpty { continuation.yield(leftover) }
        let (lock, writer) = (lock, writer)
        BlockingIO.start { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 32 * 1024)
            var failure: Error?
            while true {
                let count = read(fd, &chunk, chunk.count)
                if count > 0 {
                    continuation.yield(Data(chunk[0..<count]))
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    failure = DockerError.connectionFailed(String(cString: strerror(errno)))
                    break
                }
            }
            // Make sure no write is in flight (after shutdown they fail fast), then retire the fd.
            shutdown(fd, SHUT_RDWR)
            writer.sync {}
            lock.withLock {
                self?.finished = true
                Darwin.close(fd)
            }
            continuation.finish(throwing: failure)
        }
    }

    func send(_ data: Data) {
        writer.async { [fd, lock] in
            guard !lock.withLock({ self.finished }) else { return }
            try? UnixSocketTransport.writeAll(data, to: fd)
        }
    }

    /// Sent in order, each after the previous one, so a window drag can't leave an older size last.
    func resize(columns: Int, rows: Int) {
        let (repository, execID) = (repository, execID)
        lock.withLock {
            let previous = lastResize
            lastResize = Task {
                await previous?.value
                try? await repository.resizeExec(id: execID, columns: columns, rows: rows)
            }
        }
    }

    func close() {
        lock.withLock {
            guard !finished else { return }
            shutdown(fd, SHUT_RDWR)
        }
    }
}
