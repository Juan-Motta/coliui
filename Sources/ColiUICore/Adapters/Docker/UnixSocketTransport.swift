import Darwin
import Foundation

public protocol HTTPTransport: Sendable {
    func send(method: String, path: String, body: Data?) async throws -> HTTPResponse
}

/// Talks HTTP to the Docker Engine over a Unix domain socket (Colima exposes one per profile).
public struct UnixSocketTransport: HTTPTransport {
    public let socketPath: String
    /// `docker stop` waits up to 10 s for a graceful shutdown, so leave headroom.
    public var timeoutSeconds: Int = 30

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func send(method: String, path: String, body: Data?) async throws -> HTTPResponse {
        let request = HTTPMessage.request(method: method, path: path, body: body)
        let socketPath = socketPath
        let timeout = timeoutSeconds
        let raw = try await BlockingIO.run {
            try Self.exchange(request, socketPath: socketPath, timeoutSeconds: timeout)
        }
        return try HTTPMessage.parseResponse(raw)
    }

    private static func exchange(_ request: Data, socketPath: String, timeoutSeconds: Int) throws -> Data {
        let fd = try connect(socketPath: socketPath, timeoutSeconds: timeoutSeconds)
        defer { close(fd) }
        try writeAll(request, to: fd)

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                response.append(chunk, count: count)
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw DockerError.connectionFailed(String(cString: strerror(errno)))
            }
        }
        return response
    }

    /// Opens a connected socket; `timeoutSeconds == 0` means reads may block indefinitely (event streams).
    static func connect(socketPath: String, timeoutSeconds: Int) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DockerError.connectionFailed(String(cString: strerror(errno))) }

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < capacity else {
            close(fd)
            throw DockerError.socketUnavailable(path: socketPath)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, socketPath, capacity - 1) }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw DockerError.socketUnavailable(path: socketPath)
        }
        return fd
    }

    static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw DockerError.connectionFailed(String(cString: strerror(errno))) }
                offset += written
            }
        }
    }
}

public enum DockerSocket {
    /// Honors a `unix://` DOCKER_HOST, otherwise uses the Colima profile socket.
    public static func resolve(environment: [String: String], home: String, profile: String = "default") -> String {
        if let host = environment["DOCKER_HOST"], host.hasPrefix("unix://") {
            return String(host.dropFirst("unix://".count))
        }
        return "\(home)/.colima/\(profile)/docker.sock"
    }
}
