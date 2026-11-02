import Foundation
import Testing
@testable import ColiUICore

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Call: Equatable { let method: String; let path: String }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var response: HTTPResponse

    init(response: HTTPResponse) { self.response = response }

    var calls: [Call] { lock.withLock { _calls } }

    func send(method: String, path: String, body: Data?) async throws -> HTTPResponse {
        lock.withLock { _calls.append(Call(method: method, path: path)) }
        return response
    }
}

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

@Suite struct DockerEngineRepositoryTests {
    static let listJSON = """
    [{"Id":"e81b3f0c55d2aaaabbbb","Names":["/api-server"],"Image":"myapp/api:latest","State":"running",
      "Status":"Up 12 minutes",
      "Ports":[{"IP":"0.0.0.0","PrivatePort":8080,"PublicPort":8080,"Type":"tcp"},
               {"IP":"::","PrivatePort":8080,"PublicPort":8080,"Type":"tcp"},
               {"PrivatePort":9229,"Type":"tcp"}],
      "Labels":{"com.docker.compose.project":"shop","com.docker.compose.service":"api",
                "com.docker.compose.project.config_files":"/Users/me/shop/docker-compose.yml,/Users/me/shop/override.yml"}},
     {"Id":"5b6e28d1f034cccc","Names":["/worker"],"Image":"myapp/worker","State":"weird","Status":"Exited (1) 2 hours ago",
      "Ports":[],"Labels":{}}]
    """

    @Test func listsContainersMappedToDomain() async throws {
        let transport = FakeTransport(response: response(200, Self.listJSON))
        let containers = try await DockerEngineRepository(transport: transport).listContainers()

        #expect(transport.calls == [.init(method: "GET", path: "/containers/json?all=1")])
        #expect(containers.count == 2)
        let api = containers[0]
        #expect(api.name == "api-server")
        #expect(api.shortID == "e81b3f0c55d2")
        #expect(api.state == .running)
        #expect(api.composeProject == "shop")
        #expect(api.composeService == "api")
        #expect(api.composeConfigFile == "/Users/me/shop/docker-compose.yml")
        #expect(containers[1].composeService == nil)
        #expect(api.ports == [
            PortMapping(privatePort: 8080, publicPort: 8080, proto: "tcp"),
            PortMapping(privatePort: 9229, publicPort: nil, proto: "tcp"),
        ])
        #expect(api.portsDisplay == "8080→8080, 9229/tcp")
        #expect(containers[1].state == .unknown)
        #expect(containers[1].composeProject == nil)
    }

    @Test(arguments: [
        ("start", "POST", "/containers/abc123/start"),
        ("stop", "POST", "/containers/abc123/stop"),
        ("restart", "POST", "/containers/abc123/restart"),
    ])
    func lifecycleActionsHitTheRightEndpoint(action: String, method: String, path: String) async throws {
        let transport = FakeTransport(response: response(204))
        let repo = DockerEngineRepository(transport: transport)
        switch action {
        case "start": try await repo.start(id: "abc123")
        case "stop": try await repo.stop(id: "abc123")
        default: try await repo.restart(id: "abc123")
        }
        #expect(transport.calls == [.init(method: method, path: path)])
    }

    @Test func removeSendsForceFlag() async throws {
        let transport = FakeTransport(response: response(204))
        try await DockerEngineRepository(transport: transport).remove(id: "abc123", force: true)
        #expect(transport.calls == [.init(method: "DELETE", path: "/containers/abc123?force=true")])
    }

    @Test func notModifiedIsTreatedAsSuccess() async throws {
        let transport = FakeTransport(response: response(304))
        try await DockerEngineRepository(transport: transport).start(id: "abc123")
    }

    @Test func surfacesEngineErrorMessage() async {
        let transport = FakeTransport(response: response(409, #"{"message":"container is running"}"#))
        await #expect(throws: DockerError.requestFailed(status: 409, message: "container is running")) {
            try await DockerEngineRepository(transport: transport).remove(id: "abc123", force: false)
        }
    }

    @Test func rejectsUnsafeContainerIDs() async {
        let transport = FakeTransport(response: response(204))
        await #expect(throws: DockerError.invalidContainerID) {
            try await DockerEngineRepository(transport: transport).stop(id: "../images/x")
        }
        #expect(transport.calls.isEmpty)
    }
}

@Suite struct DockerSocketTests {
    @Test func prefersUnixDockerHost() {
        let path = DockerSocket.resolve(environment: ["DOCKER_HOST": "unix:///tmp/d.sock"], home: "/Users/me")
        #expect(path == "/tmp/d.sock")
    }

    @Test func fallsBackToColimaProfileSocket() {
        #expect(DockerSocket.resolve(environment: [:], home: "/Users/me") == "/Users/me/.colima/default/docker.sock")
        #expect(DockerSocket.resolve(environment: ["DOCKER_HOST": "tcp://1.2.3.4:2375"], home: "/Users/me", profile: "work")
            == "/Users/me/.colima/work/docker.sock")
    }
}
