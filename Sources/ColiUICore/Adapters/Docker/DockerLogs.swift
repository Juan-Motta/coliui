import Darwin
import Foundation

/// Incrementally strips HTTP headers and chunked framing from a streamed response.
public struct ChunkedBodyDecoder {
    public private(set) var statusCode: Int?
    private var buffer = Data()
    private var headersDone = false
    private var chunked = false
    private var remaining = 0
    private var expectingChunkEnd = false
    private var finished = false

    public init() {}

    public mutating func feed(_ data: Data) -> Data {
        buffer.append(data)
        if !headersDone {
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return Data() }
            let head = String(decoding: buffer.subdata(in: 0..<end.lowerBound), as: UTF8.self)
            let statusParts = head.prefix { $0 != "\r" }.split(separator: " ")
            statusCode = statusParts.count > 1 ? Int(statusParts[1]) : nil
            chunked = head.lowercased().contains("transfer-encoding: chunked")
            buffer = buffer.subdata(in: end.upperBound..<buffer.endIndex)
            headersDone = true
        }
        guard chunked else {
            defer { buffer = Data() }
            return buffer
        }

        let crlf = Data("\r\n".utf8)
        var body = Data()
        while !finished {
            if remaining > 0 {
                guard !buffer.isEmpty else { break }
                let take = min(remaining, buffer.count)
                body.append(buffer.subdata(in: 0..<take))
                buffer = buffer.subdata(in: take..<buffer.endIndex)
                remaining -= take
                expectingChunkEnd = remaining == 0
            } else if expectingChunkEnd {
                guard buffer.count >= 2 else { break }
                buffer = buffer.subdata(in: 2..<buffer.endIndex)
                expectingChunkEnd = false
            } else {
                guard let lineEnd = buffer.range(of: crlf) else { break }
                let sizeField = String(decoding: buffer.subdata(in: 0..<lineEnd.lowerBound), as: UTF8.self)
                    .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                buffer = buffer.subdata(in: lineEnd.upperBound..<buffer.endIndex)
                guard let size = Int(sizeField, radix: 16) else { continue }
                if size == 0 { finished = true } else { remaining = size }
            }
        }
        return body
    }
}

public struct RawLogLine: Sendable, Equatable {
    public let stream: LogStreamKind
    public let text: String

    public init(stream: LogStreamKind, text: String) {
        self.stream = stream
        self.text = text
    }
}

/// Turns Docker log bytes into lines. Non-TTY containers interleave stdout/stderr in frames with an
/// 8-byte header (stream type, 3 zero bytes, big-endian payload size); TTY containers send raw bytes.
public struct DockerLogDecoder {
    private let multiplexed: Bool
    private var buffer = Data()
    private var partial: [LogStreamKind: Data] = [:]

    public init(multiplexed: Bool) {
        self.multiplexed = multiplexed
    }

    public mutating func feed(_ data: Data) -> [RawLogLine] {
        guard multiplexed else { return append(data, to: .stdout) }
        buffer.append(data)
        var lines: [RawLogLine] = []
        while buffer.count >= 8 {
            let header = [UInt8](buffer.subdata(in: 0..<8))
            let size = Int(header[4]) << 24 | Int(header[5]) << 16 | Int(header[6]) << 8 | Int(header[7])
            guard buffer.count >= 8 + size else { break }
            let payload = buffer.subdata(in: 8..<(8 + size))
            buffer = buffer.subdata(in: (8 + size)..<buffer.endIndex)
            lines += append(payload, to: header[0] == 2 ? .stderr : .stdout)
        }
        return lines
    }

    public mutating func flush() -> [RawLogLine] {
        defer { partial = [:] }
        return [LogStreamKind.stdout, .stderr].compactMap { stream in
            guard let data = partial[stream], !data.isEmpty else { return nil }
            return RawLogLine(stream: stream, text: Self.text(data))
        }
    }

    private mutating func append(_ data: Data, to stream: LogStreamKind) -> [RawLogLine] {
        var pending = partial[stream] ?? Data()
        pending.append(data)
        var lines: [RawLogLine] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(RawLogLine(stream: stream, text: Self.text(pending.subdata(in: pending.startIndex..<newline))))
            pending = pending.subdata(in: pending.index(after: newline)..<pending.endIndex)
        }
        partial[stream] = pending
        return lines
    }

    private static func text(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}

/// Splits Docker's RFC 3339 timestamp prefix and recognises a log level in the message.
public enum LogLineParser {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole = ISO8601DateFormatter()

    private static let levels: [String: LogLevel] = [
        "trace": .debug, "debug": .debug,
        "info": .info, "notice": .info,
        "warn": .warn, "warning": .warn,
        "error": .error, "err": .error, "fatal": .error, "panic": .error, "crit": .error, "critical": .error,
    ]

    public static func parse(_ raw: String) -> (timestamp: Date?, level: LogLevel?, message: String) {
        var timestamp: Date?
        var message = raw
        if let space = raw.firstIndex(of: " "), let date = parseTimestamp(String(raw[..<space])) {
            timestamp = date
            message = String(raw[raw.index(after: space)...])
        }
        if let (level, rest) = leadingLevel(message) {
            return (timestamp, level, rest)
        }
        return (timestamp, keyValueLevel(message), message)
    }

    static func parseTimestamp(_ text: String) -> Date? {
        guard text.count >= 20, text.first?.isNumber == true else { return nil }
        // ISO8601DateFormatter reads at most milliseconds; Docker sends nanoseconds.
        let trimmed = text.replacingOccurrences(of: #"\.(\d{3})\d*"#, with: ".$1", options: .regularExpression)
        return fractional.date(from: trimmed) ?? whole.date(from: trimmed)
    }

    private static func leadingLevel(_ message: String) -> (LogLevel, String)? {
        let token = message.prefix { $0 != " " }
        let word = token.trimmingCharacters(in: CharacterSet(charactersIn: "[]():")).lowercased()
        guard let level = levels[word] else { return nil }
        let rest = message.dropFirst(token.count).drop { $0 == " " }
        return (level, String(rest))
    }

    private static func keyValueLevel(_ message: String) -> LogLevel? {
        guard let range = message.range(of: #"level=\"?([A-Za-z]+)"#, options: .regularExpression) else { return nil }
        let value = message[range].dropFirst("level=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
        return levels[value]
    }
}

public enum DockerLogs {
    public static func path(id: String, since: Date?, tail: Int, follow: Bool) -> String {
        var path = "/containers/\(id)/logs?follow=\(follow ? 1 : 0)&stdout=1&stderr=1&timestamps=1&tail=\(tail)"
        if let since { path += "&since=\(Int(since.timeIntervalSince1970))" }
        return path
    }
}

/// `ContainerLogSource` that follows `/containers/{id}/logs` over the Colima socket.
public struct DockerLogStream: ContainerLogSource {
    private let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func logs(id: String, since: Date?, tail: Int, tty: Bool) -> AsyncThrowingStream<LogLine, Error> {
        let socketPath = socketPath
        return AsyncThrowingStream { continuation in
            let socket = StreamingSocket()
            continuation.onTermination = { _ in socket.cancel() }
            BlockingIO.start {
                do {
                    let id = try DockerEngineRepository.validated(id)
                    let path = DockerLogs.path(id: id, since: since, tail: tail, follow: true)
                    var http = ChunkedBodyDecoder()
                    var decoder = DockerLogDecoder(multiplexed: !tty)
                    var nextID = 0
                    func emit(_ raw: RawLogLine) {
                        let parsed = LogLineParser.parse(raw.text)
                        continuation.yield(LogLine(
                            id: nextID, timestamp: parsed.timestamp, level: parsed.level,
                            message: parsed.message, stream: raw.stream
                        ))
                        nextID += 1
                    }

                    try socket.run(socketPath: socketPath, request: HTTPMessage.request(method: "GET", path: path, body: nil)) { data in
                        let body = http.feed(data)
                        if let status = http.statusCode, status >= 400 {
                            throw DockerError.requestFailed(status: status, message: "Couldn't read logs (HTTP \(status)).")
                        }
                        decoder.feed(body).forEach(emit)
                    }
                    decoder.flush().forEach(emit)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
