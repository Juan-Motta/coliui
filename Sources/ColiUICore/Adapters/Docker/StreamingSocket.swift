import Darwin
import Foundation

/// One streaming request over the Docker socket (logs, events, pulls), read on the calling thread.
/// It owns the descriptor: `cancel()` only shuts down a socket that is still open, and `run` closes it
/// exactly once, under the same lock. So a late cancel can never hit a descriptor number that was
/// closed and already reused by another connection, and a cancel during connect still closes it.
final class StreamingSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var cancelled = false

    /// Connects, sends `request`, then hands each chunk to `onChunk` until the engine closes the stream,
    /// `cancel()` is called, or `onChunk` throws. Blocks; call it from `BlockingIO.start`.
    func run(socketPath: String, request: Data, onChunk: (Data) throws -> Void) throws {
        let fd = try UnixSocketTransport.connect(socketPath: socketPath, timeoutSeconds: 0)
        let adopted = lock.withLock {
            guard !cancelled else { return false }
            self.fd = fd
            return true
        }
        guard adopted else {
            Darwin.close(fd)
            return
        }
        defer { closeOnce() }
        try UnixSocketTransport.writeAll(request, to: fd)
        var chunk = [UInt8](repeating: 0, count: 32 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                try onChunk(Data(chunk[0..<count]))
            } else if count == 0 || lock.withLock({ cancelled }) {
                return
            } else if errno != EINTR {
                throw DockerError.connectionFailed(String(cString: strerror(errno)))
            }
        }
    }

    /// Ends the stream: the blocked read returns and `run` closes the socket.
    func cancel() {
        lock.withLock {
            cancelled = true
            if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        }
    }

    private func closeOnce() {
        lock.withLock {
            guard fd >= 0 else { return }
            Darwin.close(fd)
            fd = -1
        }
    }
}
