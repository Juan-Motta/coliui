import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

/// Answers by path, recording each call.
private final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _paths: [String] = []
    let routes: [String: HTTPResponse]

    init(_ routes: [String: HTTPResponse]) { self.routes = routes }
    var paths: [String] { lock.withLock { _paths } }

    func send(method: String, path: String, body: Data?) async throws -> HTTPResponse {
        lock.withLock { _paths.append(path) }
        return routes[path] ?? response(404, #"{"message":"not found"}"#)
    }
}

@Suite struct EnvironmentEntryTests {
    @Test func marksImageVariablesAndKeepsDockerOrder() {
        let variables = EnvironmentEntry.list(
            container: ["PATH=/usr/bin:/bin", "NODE_VERSION=22", "PORT=8080", "DB_PASSWORD=x", "EMPTY", "JSON=a=b"],
            image: ["PATH=/usr/bin:/bin", "NODE_VERSION=20"]
        )

        #expect(variables == [
            EnvironmentEntry(name: "PATH", value: "/usr/bin:/bin", source: .image, isSecret: false),
            EnvironmentEntry(name: "NODE_VERSION", value: "22", source: .container, isSecret: false),
            EnvironmentEntry(name: "PORT", value: "8080", source: .container, isSecret: false),
            EnvironmentEntry(name: "DB_PASSWORD", value: "x", source: .container, isSecret: true),
            EnvironmentEntry(name: "EMPTY", value: "", source: .container, isSecret: false),
            EnvironmentEntry(name: "JSON", value: "a=b", source: .container, isSecret: false),
        ])
    }

    @Test func secretRuleMatchesInspect() {
        #expect(SecretMask.isSecret("GITHUB_TOKEN=abc"))
        #expect(SecretMask.isSecret("DATABASE_URL=postgres://app:pw@db/shop"))
        #expect(!SecretMask.isSecret("REDIS_URL=redis://cache:6379"))
        #expect(!SecretMask.isSecret("API_TOKEN="))
    }
}

@Suite struct DockerEnvironmentTests {
    @Test func readsContainerAndImageEnvironment() async throws {
        let transport = RoutedTransport([
            "/containers/c1/json": response(200, #"{"Image":"sha256:4f1c8a3e9b2d","Config":{"Env":["PATH=/bin","PORT=8080"]}}"#),
            "/images/sha256:4f1c8a3e9b2d/json": response(200, #"{"Config":{"Env":["PATH=/bin"]}}"#),
        ])
        let variables = try await DockerEngineRepository(transport: transport).environment(id: "c1")

        #expect(transport.paths == ["/containers/c1/json", "/images/sha256:4f1c8a3e9b2d/json"])
        #expect(variables.map(\.source) == [.image, .container])
    }

    /// The image may be gone (removed with --force); its variables then can't be told apart.
    @Test func treatsEverythingAsContainerWhenTheImageIsMissing() async throws {
        let transport = RoutedTransport([
            "/containers/c1/json": response(200, #"{"Image":"sha256:4f1c8a3e9b2d","Config":{"Env":["PATH=/bin"]}}"#),
        ])
        let variables = try await DockerEngineRepository(transport: transport).environment(id: "c1")
        #expect(variables.map(\.source) == [.container])
    }

    @Test func refusesAnUnsafeImageID() async throws {
        let transport = RoutedTransport([
            "/containers/c1/json": response(200, #"{"Image":"../../containers/x","Config":{"Env":["PATH=/bin"]}}"#),
        ])
        let variables = try await DockerEngineRepository(transport: transport).environment(id: "c1")
        #expect(transport.paths == ["/containers/c1/json"])
        #expect(variables.map(\.source) == [.container])
    }

    @Test func surfacesContainerErrors() async {
        let transport = RoutedTransport([:])
        await #expect(throws: DockerError.requestFailed(status: 404, message: "not found")) {
            try await DockerEngineRepository(transport: transport).environment(id: "c1")
        }
    }
}
