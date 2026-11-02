import Darwin
import Foundation

extension DockerEngineRepository: ImageRepository {
    public func images() async throws -> [DockerImage] {
        let response = try await transport.send(method: "GET", path: "/images/json", body: nil)
        try Self.check(response)
        guard let dtos = try? JSONDecoder().decode([ImageDTO].self, from: response.body) else {
            throw DockerError.malformedResponse
        }
        return dtos.flatMap { $0.toDomain() }
    }

    public func removeImage(_ reference: String) async throws {
        let reference = try Self.validatedImageReference(reference)
        let response = try await transport.send(method: "DELETE", path: "/images/\(reference)?force=false", body: nil)
        try Self.check(response)
    }

    /// References only use `[A-Za-z0-9_.-:/@]`; anything else could escape the path or add query parameters.
    static func validatedImageReference(_ reference: String) throws -> String {
        let allowed = DockerEngineRepository.asciiAlphanumerics.union(CharacterSet(charactersIn: "_.-:/@"))
        guard !reference.isEmpty, !reference.hasPrefix("."), !reference.hasPrefix("/"), !reference.contains(".."),
              reference.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DockerError.invalidContainerID
        }
        return reference
    }
}

private struct ImageDTO: Decodable {
    let id: String
    let repoTags: [String]?
    let created: Int64
    let size: Int64
    enum CodingKeys: String, CodingKey { case id = "Id", repoTags = "RepoTags", created = "Created", size = "Size" }

    func toDomain() -> [DockerImage] {
        let created = Date(timeIntervalSince1970: TimeInterval(created))
        let tags = (repoTags ?? []).filter { $0 != "<none>:<none>" }
        guard !tags.isEmpty else {
            return [DockerImage(imageID: id, repository: "<none>", tag: "<none>", created: created, size: size)]
        }
        return tags.map { tag in
            let parts = RunRequest.imageParts(tag)
            return DockerImage(imageID: id, repository: parts.repository, tag: parts.tag, created: created, size: size)
        }
    }
}

public enum DockerImagePull {
    public static func path(for reference: String) -> String {
        let parts = RunRequest.imageParts(reference)
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))
        let repository = parts.repository.addingPercentEncoding(withAllowedCharacters: allowed) ?? parts.repository
        let tag = parts.tag.addingPercentEncoding(withAllowedCharacters: allowed) ?? parts.tag
        return "/images/create?fromImage=\(repository)&tag=\(tag)"
    }
}

/// `ImagePuller` that streams `POST /images/create` over the Colima socket.
/// Cancelling the stream closes the connection, which makes the engine abandon the pull.
public struct DockerImagePuller: ImagePuller {
    private let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func pull(_ reference: String) -> AsyncThrowingStream<PullProgress, Error> {
        let socketPath = socketPath
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let socket = StreamingSocket()
            continuation.onTermination = { _ in socket.cancel() }
            BlockingIO.start {
                do {
                    let request = HTTPMessage.request(method: "POST", path: DockerImagePull.path(for: reference), body: nil)
                    var http = ChunkedBodyDecoder()
                    var tracker = PullProgressTracker()
                    var pending = Data()
                    try socket.run(socketPath: socketPath, request: request) { data in
                        pending.append(http.feed(data))
                        if let status = http.statusCode, status >= 400 { return }
                        var start = pending.startIndex
                        while let newline = pending[start...].firstIndex(of: UInt8(ascii: "\n")) {
                            continuation.yield(try tracker.feed(String(decoding: pending[start..<newline], as: UTF8.self)))
                            start = newline + 1
                        }
                        pending = Data(pending[start...])
                    }
                    if let status = http.statusCode, status >= 400 {
                        try DockerEngineRepository.check(HTTPResponse(statusCode: status, headers: [:], body: pending))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
