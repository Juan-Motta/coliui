import Foundation

public struct HTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    /// Header names are lowercased.
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public enum DockerError: Error, Equatable, LocalizedError {
    /// `reason` is the system's explanation (`strerror`), so a one-off failure can be diagnosed.
    case socketUnavailable(path: String, reason: String = "")
    case connectionFailed(String)
    case malformedResponse
    case invalidContainerID
    case requestFailed(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .socketUnavailable(let path, let reason):
            "Docker isn't reachable at \(path)\(reason.isEmpty ? "" : " (\(reason))"). Is Colima running?"
        case .connectionFailed(let reason): "Lost connection to Docker: \(reason)"
        case .malformedResponse: "Docker returned an unexpected response."
        case .invalidContainerID: "Invalid container identifier."
        case .requestFailed(_, let message): message
        }
    }
}

/// Minimal HTTP/1.1 framing for one request per connection (`Connection: close`).
enum HTTPMessage {
    static func request(method: String, path: String, body: Data?) -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: localhost\r\n"
        head += "User-Agent: ColiUI\r\n"
        head += "Connection: close\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        head += "Content-Length: \(body?.count ?? 0)\r\n\r\n"
        var data = Data(head.utf8)
        if let body { data.append(body) }
        return data
    }

    static func parseResponse(_ raw: Data) throws -> HTTPResponse {
        let separator = Data("\r\n\r\n".utf8)
        guard let headEnd = raw.range(of: separator) else { throw DockerError.malformedResponse }

        let head = String(decoding: raw[raw.startIndex..<headEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let statusParts = lines.removeFirst().split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/"), let status = Int(statusParts[1]) else {
            throw DockerError.malformedResponse
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        var body = Data(raw[headEnd.upperBound...])
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = try dechunk(body)
        } else if let length = headers["content-length"].flatMap(Int.init), length <= body.count {
            body = Data(body.prefix(length))
        }
        return HTTPResponse(statusCode: status, headers: headers, body: body)
    }

    private static func dechunk(_ data: Data) throws -> Data {
        let crlf = Data("\r\n".utf8)
        var output = Data()
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard let lineEnd = data.range(of: crlf, in: cursor..<data.endIndex) else { throw DockerError.malformedResponse }
            let sizeField = String(decoding: data[cursor..<lineEnd.lowerBound], as: UTF8.self)
                .split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeField.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw DockerError.malformedResponse
            }
            if size == 0 { break }
            let chunkStart = lineEnd.upperBound
            let chunkEnd = chunkStart + size
            guard chunkEnd <= data.endIndex else { throw DockerError.malformedResponse }
            output.append(data[chunkStart..<chunkEnd])
            cursor = min(chunkEnd + crlf.count, data.endIndex)
        }
        return output
    }
}
