import Darwin
import Foundation

/// Counts events in the Docker `/events` HTTP stream as bytes arrive.
/// The body is chunked; every event is one JSON object on its own line, so chunk-size lines are skipped.
public struct DockerEventDecoder {
    private var buffer = Data()
    private var headersDone = false

    public init() {}

    public mutating func feed(_ data: Data) -> Int {
        buffer.append(data)
        if !headersDone {
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return 0 }
            buffer = buffer.subdata(in: end.upperBound..<buffer.endIndex)
            headersDone = true
        }
        var events = 0
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            if buffer[buffer.startIndex] == UInt8(ascii: "{") { events += 1 }
            buffer = buffer.subdata(in: buffer.index(after: newline)..<buffer.endIndex)
        }
        return events
    }
}

public enum DockerEvents {
    /// `/events?filters={"type":["container"]}`
    public static let containerEventsPath = "/events?filters="
        + #"{"type":["container"]}"#.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

    /// Yields once per container event (start, stop, die, create, destroy, …) until the stream ends.
    /// Bursts collapse to the newest value so a consumer refreshes at most once per batch.
    public static func containerEvents(socketPath: String) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            BlockingIO.start {
                do {
                    let fd = try UnixSocketTransport.connect(socketPath: socketPath, timeoutSeconds: 0)
                    defer { close(fd) }
                    continuation.onTermination = { _ in shutdown(fd, SHUT_RDWR) }
                    try UnixSocketTransport.writeAll(
                        HTTPMessage.request(method: "GET", path: containerEventsPath, body: nil),
                        to: fd
                    )
                    var decoder = DockerEventDecoder()
                    var chunk = [UInt8](repeating: 0, count: 16 * 1024)
                    while true {
                        let count = read(fd, &chunk, chunk.count)
                        if count > 0 {
                            for _ in 0..<decoder.feed(Data(chunk[0..<count])) { continuation.yield(()) }
                        } else if count == 0 {
                            break
                        } else if errno != EINTR {
                            throw DockerError.connectionFailed(String(cString: strerror(errno)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
