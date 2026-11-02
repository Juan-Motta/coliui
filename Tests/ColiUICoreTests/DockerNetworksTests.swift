import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

@Suite struct DockerNetworkTests {
    static let json = """
    [{"Name":"shop_default","Id":"7f1c2d3e4a5b","Driver":"bridge","Internal":false,
      "IPAM":{"Config":[{"Subnet":"172.19.0.0/16","Gateway":"172.19.0.1"}]},
      "Labels":{"com.docker.compose.project":"shop","com.docker.compose.network":"default"}},
     {"Name":"host","Id":"aa11bb22cc33","Driver":"host","Internal":false,"IPAM":{"Config":[]},"Labels":{}},
     {"Name":"secure","Id":"dd44ee55ff66","Driver":"bridge","Internal":true,"IPAM":{"Config":null},"Labels":null}]
    """

    @Test func listsNetworksMappedToDomain() async throws {
        let transport = FakeTransport(response: response(200, Self.json))
        let networks = try await DockerEngineRepository(transport: transport).networks()

        #expect(transport.calls == [.init(method: "GET", path: "/networks")])
        #expect(networks.map(\.name) == ["shop_default", "host", "secure"])
        #expect(networks[0].id == "7f1c2d3e4a5b")
        #expect(networks[0].subnet == "172.19.0.0/16")
        #expect(networks[0].gateway == "172.19.0.1")
        #expect(networks[0].composeProject == "shop")
        #expect(!networks[0].isBuiltIn)
        #expect(networks[1].isBuiltIn)
        #expect(networks[1].subnet == nil)
        #expect(networks[2].isInternal)
        #expect(networks[2].gateway == nil)
    }

    @Test func createsWithDriverAndInternalFlag() async throws {
        let transport = FakeTransport(response: response(201, #"{"Id":"abc","Warning":""}"#))
        try await DockerEngineRepository(transport: transport).createNetwork(name: "backend", driver: "bridge", internal: true)

        #expect(transport.calls == [.init(method: "POST", path: "/networks/create")])
        let body = try #require(transport.bodies.first ?? nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["Name"] as? String == "backend")
        #expect(json["Driver"] as? String == "bridge")
        #expect(json["Internal"] as? Bool == true)
    }

    @Test func removesByID() async throws {
        let transport = FakeTransport(response: response(204))
        try await DockerEngineRepository(transport: transport).removeNetwork(id: "7f1c2d3e4a5b")
        #expect(transport.calls == [.init(method: "DELETE", path: "/networks/7f1c2d3e4a5b")])
    }

    @Test func surfacesActiveEndpoints() async {
        let transport = FakeTransport(response: response(403, #"{"message":"error while removing network: network shop_default has active endpoints"}"#))
        await #expect(throws: DockerError.requestFailed(status: 403, message: "error while removing network: network shop_default has active endpoints")) {
            try await DockerEngineRepository(transport: transport).removeNetwork(id: "7f1c2d3e4a5b")
        }
    }

    @Test func rejectsUnsafeIDs() async {
        let transport = FakeTransport(response: response(204))
        await #expect(throws: DockerError.invalidContainerID) {
            try await DockerEngineRepository(transport: transport).removeNetwork(id: "../containers/x")
        }
        #expect(transport.calls.isEmpty)
    }
}
