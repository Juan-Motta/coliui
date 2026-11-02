import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

private let hexA = String(repeating: "4be1c0", count: 10) + "abcd"
private let hexB = String(repeating: "08ab77", count: 10) + "ef01"

@Suite struct DockerImageListTests {
    static let json = """
    [{"Id":"sha256:\(hexA)","RepoTags":["myapp/api:latest","myapp/api:1.2"],"Created":1700000000,"Size":412000000},
     {"Id":"sha256:\(hexB)","RepoTags":null,"Created":1700000100,"Size":386000000}]
    """

    @Test func listsOneRowPerTagAndDanglingImages() async throws {
        let transport = FakeTransport(response: response(200, Self.json))
        let images = try await DockerEngineRepository(transport: transport).images()

        #expect(transport.calls == [.init(method: "GET", path: "/images/json")])
        #expect(images.map(\.repository) == ["myapp/api", "myapp/api", "<none>"])
        #expect(images.map(\.tag) == ["latest", "1.2", "<none>"])
        #expect(Set(images.map(\.id)).count == 3)
        #expect(images[0].imageID == "sha256:\(hexA)")
        #expect(images[0].shortID == "sha256:4be1c0")
        #expect(images[0].created == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(images[0].size == 412_000_000)
        #expect(images[0].reference == "myapp/api:latest")
        #expect(!images[0].isDangling)
        #expect(images[2].isDangling)
        #expect(images[2].reference == hexB)
    }

    @Test func treatsNoneTagsAsDangling() async throws {
        let body = #"[{"Id":"sha256:\#(hexB)","RepoTags":["<none>:<none>"],"Created":1,"Size":1}]"#
        let images = try await DockerEngineRepository(transport: FakeTransport(response: response(200, body))).images()
        #expect(images.count == 1)
        #expect(images[0].isDangling)
    }
}

@Suite struct DockerImageRemoveTests {
    @Test func removesTaggedImagesByReference() async throws {
        let transport = FakeTransport(response: response(200, "[]"))
        try await DockerEngineRepository(transport: transport).removeImage("localhost:5000/team/api:2.1")
        #expect(transport.calls == [.init(method: "DELETE", path: "/images/localhost:5000/team/api:2.1?force=false")])
    }

    @Test func surfacesConflicts() async {
        let transport = FakeTransport(response: response(409, #"{"message":"image is being used by running container e81b"}"#))
        await #expect(throws: DockerError.requestFailed(status: 409, message: "image is being used by running container e81b")) {
            try await DockerEngineRepository(transport: transport).removeImage("nginx:1.27")
        }
    }

    @Test(arguments: ["", "../containers/abc", "nginx?force=true", "a b"])
    func rejectsUnsafeReferences(reference: String) async {
        let transport = FakeTransport(response: response(200))
        await #expect(throws: DockerError.invalidContainerID) {
            try await DockerEngineRepository(transport: transport).removeImage(reference)
        }
        #expect(transport.calls.isEmpty)
    }
}

@Suite struct PullProgressTests {
    @Test func pathSplitsTheReference() {
        #expect(DockerImagePull.path(for: "python:3.13-slim") == "/images/create?fromImage=python&tag=3.13-slim")
        #expect(DockerImagePull.path(for: "nginx") == "/images/create?fromImage=nginx&tag=latest")
        #expect(DockerImagePull.path(for: "nginx@sha256:4f1c8a3e9b2d") == "/images/create?fromImage=nginx&tag=sha256:4f1c8a3e9b2d")
    }

    @Test func aggregatesLayerDownloadsThenExtraction() throws {
        var tracker = PullProgressTracker()
        #expect(try tracker.feed(#"{"status":"Pulling from library/python","id":"3.13-slim"}"#) == PullProgress(phase: .waiting, fraction: nil))
        _ = try tracker.feed(#"{"status":"Pulling fs layer","id":"a"}"#)
        _ = try tracker.feed(#"{"status":"Downloading","progressDetail":{"current":30,"total":100},"id":"a"}"#)
        let downloading = try tracker.feed(#"{"status":"Downloading","progressDetail":{"current":32,"total":100},"id":"b"}"#)
        #expect(downloading == PullProgress(phase: .downloading, fraction: 0.31))
        #expect(downloading.title == "Downloading 31%")
        _ = try tracker.feed(#"{"status":"Download complete","id":"a"}"#)
        let extracting = try tracker.feed(#"{"status":"Extracting","progressDetail":{"current":25,"total":100},"id":"a"}"#)
        #expect(extracting == PullProgress(phase: .extracting, fraction: 0.25))
        #expect(extracting.title == "Extracting 25%")
        #expect(try tracker.feed(#"{"status":"Status: Downloaded newer image for python:3.13-slim"}"#).phase == .done)
    }

    @Test func throwsTheStreamError() {
        var tracker = PullProgressTracker()
        #expect(throws: DockerError.requestFailed(status: 200, message: "manifest unknown")) {
            try tracker.feed(#"{"errorDetail":{"message":"manifest unknown"},"error":"manifest unknown"}"#)
        }
    }
}

@Suite struct ImageAgeTests {
    private let now = Date(timeIntervalSince1970: 10_000_000)

    @Test(arguments: [
        (30.0, "just now"), (60, "1 min ago"), (12 * 60, "12 min ago"), (3600, "1 hour ago"),
        (2 * 3600, "2 hours ago"), (5 * 86_400, "5 days ago"), (21 * 86_400, "3 weeks ago"),
        (40 * 86_400, "1 month ago"), (70 * 86_400, "2 months ago"), (800 * 86_400, "2 years ago"),
    ] as [(Double, String)])
    func formatsAges(seconds: Double, text: String) {
        #expect(ImageAge.text(for: now.addingTimeInterval(-seconds), now: now) == text)
    }
}
