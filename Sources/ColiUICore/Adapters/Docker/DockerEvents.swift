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
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: UInt8(ascii: "\n")) {
            if start < newline, buffer[start] == UInt8(ascii: "{") { events += 1 }
            start = newline + 1
        }
        buffer = Data(buffer[start...])
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
            let socket = StreamingSocket()
            continuation.onTermination = { _ in socket.cancel() }
            BlockingIO.start {
                do {
                    var decoder = DockerEventDecoder()
                    let request = HTTPMessage.request(method: "GET", path: containerEventsPath, body: nil)
                    try socket.run(socketPath: socketPath, request: request) { data in
                        for _ in 0..<decoder.feed(data) { continuation.yield(()) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
