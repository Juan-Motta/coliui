import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

private let anonymousName = "9f3c1e0b7a2d4c58e61b0a9d3f7e2c419f3c1e0b7a2d4c58e61b0a9d3f7e2c41"

@Suite struct DockerVolumeTests {
    static let json = """
    {"Volumes":[
      {"Name":"shop_pgdata","Driver":"local","CreatedAt":"2026-10-11T09:30:00Z",
       "Labels":{"com.docker.compose.project":"shop","com.docker.compose.volume":"pgdata"},
       "UsageData":{"RefCount":1,"Size":612000000}},
      {"Name":"\(anonymousName)","Driver":"local","CreatedAt":"2026-10-26T10:00:00Z","Labels":null,
       "UsageData":{"RefCount":0,"Size":-1}},
      {"Name":"tagged-anon","Driver":"local","Labels":{"com.docker.volume.anonymous":""}}
    ]}
    """

    @Test func listsVolumesWithSizesFromDiskUsage() async throws {
        let transport = FakeTransport(response: response(200, Self.json))
        let volumes = try await DockerEngineRepository(transport: transport).volumes()

        #expect(transport.calls == [.init(method: "GET", path: "/system/df?type=volume")])
        #expect(volumes.map(\.name) == ["shop_pgdata", anonymousName, "tagged-anon"])
        #expect(volumes[0].driver == "local")
        #expect(volumes[0].composeProject == "shop")
        #expect(volumes[0].size == 612_000_000)
        #expect(volumes[0].created == ISO8601DateFormatter().date(from: "2026-10-11T09:30:00Z"))
        #expect(!volumes[0].isAnonymous)
        #expect(volumes[1].size == nil)
        #expect(volumes[1].isAnonymous)
        #expect(volumes[2].isAnonymous)
        #expect(volumes[2].created == nil)
    }

    @Test func createsALocalVolume() async throws {
        let transport = FakeTransport(response: response(201, #"{"Name":"minio-data"}"#))
        try await DockerEngineRepository(transport: transport).createVolume(name: "minio-data")

        #expect(transport.calls == [.init(method: "POST", path: "/volumes/create")])
        let body = try #require(transport.bodies.first ?? nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["Name": "minio-data", "Driver": "local"])
    }

    @Test func removesByName() async throws {
        let transport = FakeTransport(response: response(204))
        try await DockerEngineRepository(transport: transport).removeVolume(name: "legacy_mysql")
        #expect(transport.calls == [.init(method: "DELETE", path: "/volumes/legacy_mysql?force=false")])
    }

    @Test func surfacesVolumeInUse() async {
        let transport = FakeTransport(response: response(409, #"{"message":"remove shop_pgdata: volume is in use - [e81b]"}"#))
        await #expect(throws: DockerError.requestFailed(status: 409, message: "remove shop_pgdata: volume is in use - [e81b]")) {
            try await DockerEngineRepository(transport: transport).removeVolume(name: "shop_pgdata")
        }
    }

    @Test(arguments: ["", "../images/x", "a/b", "a b"])
    func rejectsUnsafeNames(name: String) async {
        let transport = FakeTransport(response: response(204))
        await #expect(throws: DockerError.invalidContainerID) {
            try await DockerEngineRepository(transport: transport).removeVolume(name: name)
        }
        #expect(transport.calls.isEmpty)
    }
}
