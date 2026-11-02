import Foundation
import Testing
@testable import ColiUICore

private func ok(_ body: String = "") -> HTTPResponse { HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8)) }
private func status(_ code: Int, _ body: String = "") -> HTTPResponse { HTTPResponse(statusCode: code, headers: [:], body: Data(body.utf8)) }

private let postgres = RunRequest(
    image: "postgres:16-alpine",
    name: "postgres-test",
    ports: [PortBinding(hostPort: 5433, containerPort: 5432, proto: "tcp")],
    volumes: [VolumeBinding(source: "pgdata", target: "/var/lib/postgresql/data")],
    environment: [EnvironmentVariable(key: "POSTGRES_PASSWORD", value: "example")],
    restartPolicy: .unlessStopped,
    autoRemove: false,
    pull: false
)

@Suite struct RunRequestTests {
    @Test func rendersTheEquivalentCommandWithSecretsMasked() {
        #expect(postgres.dockerRunCommand(maskSecrets: true) == """
        docker run -d --name postgres-test \\
          -p 5433:5432 \\
          -v pgdata:/var/lib/postgresql/data \\
          -e POSTGRES_PASSWORD=•••••• \\
          --restart unless-stopped \\
          postgres:16-alpine
        """)
        #expect(postgres.dockerRunCommand(maskSecrets: false).contains("-e POSTGRES_PASSWORD=example"))
    }

    @Test func minimalCommandHasOnlyTheImage() {
        let request = RunRequest(image: "nginx", name: nil, ports: [], volumes: [], environment: [],
                                 restartPolicy: .no, autoRemove: true, pull: false)
        #expect(request.dockerRunCommand(maskSecrets: true) == "docker run -d --rm \\\n  nginx")
    }

    @Test(arguments: [
        ("postgres:16-alpine", "postgres", "16-alpine"),
        ("nginx", "nginx", "latest"),
        ("localhost:5000/team/api:2.1", "localhost:5000/team/api", "2.1"),
        ("localhost:5000/team/api", "localhost:5000/team/api", "latest"),
        // Pinned by digest: Docker takes the digest where the tag goes.
        ("nginx@sha256:4f1c8a3e9b2d", "nginx", "sha256:4f1c8a3e9b2d"),
        ("localhost:5000/team/api:2.1@sha256:4f1c8a3e9b2d", "localhost:5000/team/api", "sha256:4f1c8a3e9b2d"),
    ])
    func splitsImageReferences(reference: String, repository: String, tag: String) {
        let parts = RunRequest.imageParts(reference)
        #expect(parts.repository == repository)
        #expect(parts.tag == tag)
    }
}

@Suite struct ContainerRunnerTests {
    @Test func createsWithTheRightBodyThenStarts() async throws {
        let transport = FakeTransport(response: status(204))
        transport.scripted["/containers/create"] = [status(201, #"{"Id":"abc123def456","Warnings":[]}"#)]
        let id = try await DockerEngineRepository(transport: transport).run(postgres)

        #expect(id == "abc123def456")
        #expect(transport.calls == [
            .init(method: "POST", path: "/containers/create?name=postgres-test"),
            .init(method: "POST", path: "/containers/abc123def456/start"),
        ])
        let body = try #require(transport.bodies.first ?? nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["Image"] as? String == "postgres:16-alpine")
        #expect(json["Env"] as? [String] == ["POSTGRES_PASSWORD=example"])
        #expect((json["ExposedPorts"] as? [String: Any])?.keys.sorted() == ["5432/tcp"])
        let host = try #require(json["HostConfig"] as? [String: Any])
        #expect(host["Binds"] as? [String] == ["pgdata:/var/lib/postgresql/data"])
        #expect(host["AutoRemove"] as? Bool == false)
        let restart = try #require(host["RestartPolicy"] as? [String: Any])
        #expect(restart["Name"] as? String == "unless-stopped")
        let bindings = try #require(host["PortBindings"] as? [String: [[String: String]]])
        #expect(bindings["5432/tcp"]?.first?["HostPort"] == "5433")
    }

    @Test func pullsFirstWhenAsked() async throws {
        let transport = FakeTransport(response: status(204))
        transport.scripted["/images/create"] = [ok(#"{"status":"Pulling"}"# + "\n" + #"{"status":"Done"}"#)]
        transport.scripted["/containers/create"] = [status(201, #"{"Id":"abc"}"#)]
        var request = postgres
        request.pull = true
        _ = try await DockerEngineRepository(transport: transport).run(request)

        #expect(transport.calls.map(\.path) == [
            "/images/create?fromImage=postgres&tag=16-alpine",
            "/containers/create?name=postgres-test",
            "/containers/abc/start",
        ])
    }

    @Test func pullsAndRetriesWhenTheImageIsMissing() async throws {
        let transport = FakeTransport(response: status(204))
        transport.scripted["/containers/create"] = [
            status(404, #"{"message":"No such image: postgres:16-alpine"}"#),
            status(201, #"{"Id":"abc"}"#),
        ]
        transport.scripted["/images/create"] = [ok(#"{"status":"Done"}"#)]
        _ = try await DockerEngineRepository(transport: transport).run(postgres)

        #expect(transport.calls.map(\.path) == [
            "/containers/create?name=postgres-test",
            "/images/create?fromImage=postgres&tag=16-alpine",
            "/containers/create?name=postgres-test",
            "/containers/abc/start",
        ])
    }

    @Test func surfacesPullErrorsFromTheStream() async {
        let transport = FakeTransport(response: status(204))
        transport.scripted["/images/create"] = [ok(#"{"status":"Pulling"}"# + "\n" + #"{"error":"manifest unknown"}"#)]
        var request = postgres
        request.pull = true
        await #expect(throws: DockerError.requestFailed(status: 200, message: "manifest unknown")) {
            try await DockerEngineRepository(transport: transport).run(request)
        }
    }

    @Test func omitsTheNameWhenNotGiven() async throws {
        let transport = FakeTransport(response: status(204))
        transport.scripted["/containers/create"] = [status(201, #"{"Id":"abc"}"#)]
        var request = postgres
        request.name = nil
        _ = try await DockerEngineRepository(transport: transport).run(request)
        #expect(transport.calls.first?.path == "/containers/create")
    }
}
