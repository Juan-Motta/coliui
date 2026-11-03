import Foundation
import Testing
@testable import ColiUICore

@Suite struct DockerEngineTests {
    private let home = "/Users/me"

    @Test func eachEngineHasItsKnownSocket() {
        #expect(DockerEngineKind.colima.socket(home: home, profile: "work") == "/Users/me/.colima/work/docker.sock")
        #expect(DockerEngineKind.dockerDesktop.socket(home: home, profile: "default") == "/Users/me/.docker/run/docker.sock")
        #expect(DockerEngineKind.orbStack.socket(home: home, profile: "default") == "/Users/me/.orbstack/run/docker.sock")
        #expect(DockerEngineKind.rancherDesktop.socket(home: home, profile: "default") == "/Users/me/.rd/docker.sock")
        #expect(DockerEngineKind.other.socket(home: home, profile: "default") == nil)
    }

    @Test func automaticPicksTheFirstEngineThatAnswersInOrder() {
        let answering: Set = ["/Users/me/.orbstack/run/docker.sock", "/Users/me/.docker/run/docker.sock"]
        let found = EngineDetection.automatic(environment: [:], home: home, profile: "default") { answering.contains($0) }
        #expect(found == DetectedEngine(kind: .dockerDesktop, socketPath: "/Users/me/.docker/run/docker.sock", isAnswering: true))
    }

    @Test func colimaComesFirstWhenItAnswers() {
        let found = EngineDetection.automatic(environment: [:], home: home, profile: "work") { _ in true }
        #expect(found.kind == .colima)
        #expect(found.socketPath == "/Users/me/.colima/work/docker.sock")
    }

    @Test func withNothingAnsweringItWaitsOnColima() {
        let found = EngineDetection.automatic(environment: [:], home: home, profile: "default") { _ in false }
        #expect(found == DetectedEngine(kind: .colima, socketPath: "/Users/me/.colima/default/docker.sock", isAnswering: false))
    }

    @Test func aUnixDockerHostStillWinsAndIsNamedByItsPath() {
        let orb = EngineDetection.automatic(environment: ["DOCKER_HOST": "unix:///Users/me/.orbstack/run/docker.sock"],
                                            home: home, profile: "default") { _ in false }
        #expect(orb == DetectedEngine(kind: .orbStack, socketPath: "/Users/me/.orbstack/run/docker.sock", isAnswering: false))

        let custom = EngineDetection.automatic(environment: ["DOCKER_HOST": "unix:///tmp/d.sock"],
                                               home: home, profile: "default") { _ in true }
        #expect(custom == DetectedEngine(kind: .other, socketPath: "/tmp/d.sock", isAnswering: true))

        // Any Colima profile's socket is Colima, not just the default profile's.
        let work = EngineDetection.automatic(environment: ["DOCKER_HOST": "unix:///Users/me/.colima/work/docker.sock"],
                                             home: home, profile: "default") { _ in false }
        #expect(work.kind == .colima)

        // A tcp:// host isn't a socket ColiUI can use, so detection carries on.
        let tcp = EngineDetection.automatic(environment: ["DOCKER_HOST": "tcp://1.2.3.4:2375"],
                                            home: home, profile: "default") { _ in false }
        #expect(tcp.kind == .colima)
    }

    @Test func socketPathsNameTheirEngine() {
        #expect(DockerEngineKind.owning(socketPath: "/Users/me/.colima/default/docker.sock", home: home) == .colima)
        #expect(DockerEngineKind.owning(socketPath: "/Users/me/.colima/work/docker.sock", home: home) == .colima)
        #expect(DockerEngineKind.owning(socketPath: "/Users/me/.colima/a/b/docker.sock", home: home) == .other)
        #expect(DockerEngineKind.owning(socketPath: "/Users/me/.docker/run/docker.sock", home: home) == .dockerDesktop)
        #expect(DockerEngineKind.owning(socketPath: "/tmp/d.sock", home: home) == .other)
    }

    @Test func infoNamesAnEngineReachedThroughAnotherSocket() {
        func info(_ name: String, _ os: String) -> EngineInfo {
            EngineInfo(name: name, operatingSystem: os, serverVersion: "28.5.1", cpus: 10, memoryBytes: 8 << 30)
        }
        #expect(DockerEngineKind.identify(info("docker-desktop", "Docker Desktop")) == .dockerDesktop)
        #expect(DockerEngineKind.identify(info("orbstack", "OrbStack")) == .orbStack)
        #expect(DockerEngineKind.identify(info("colima", "Ubuntu 24.04.4 LTS")) == .colima)
        #expect(DockerEngineKind.identify(info("colima-work", "Ubuntu 24.04.4 LTS")) == .colima)
        #expect(DockerEngineKind.identify(info("lima-rancher-desktop", "Rancher Desktop WSL Distribution")) == .rancherDesktop)
        #expect(DockerEngineKind.identify(info("myhost", "Ubuntu 22.04")) == .other)
    }

    @Test func infoDecodesFromTheEngineAPI() async throws {
        let body = #"{"Name":"colima","OperatingSystem":"Ubuntu 24.04.4 LTS","ServerVersion":"29.5.2","NCPU":4,"MemTotal":4095127552}"#
        let repository = DockerEngineRepository(transport: FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))))
        let info = try await repository.engineInfo()
        #expect(info == EngineInfo(name: "colima", operatingSystem: "Ubuntu 24.04.4 LTS", serverVersion: "29.5.2",
                                   cpus: 4, memoryBytes: 4_095_127_552))
        #expect(info.summary == "Engine 29.5.2 · 4 CPU · 3.8 GiB")
    }
}

@Suite struct SocketProbeTests {
    @Test func aMissingSocketDoesNotAnswer() {
        #expect(!UnixSocketTransport.answers(socketPath: "/tmp/coliui-no-such-\(UUID().uuidString).sock"))
    }
}
