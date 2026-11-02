import Foundation
import Testing
@testable import ColiUICore

/// Talks to the real Colima socket. Run with `COLIUI_LIVE=1 swift test --filter LiveDockerTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["COLIUI_LIVE"] != nil))
struct LiveDockerTests {
    let socket = DockerSocket.resolve(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())

    @Test func readsDetailsAndLogsOfTheFirstContainer() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let container = try #require(try await repository.listContainers().first { !$0.isRunning })
        let details = try await repository.details(id: container.id)

        var lines: [LogLine] = []
        for try await line in DockerLogStream(socketPath: socket).logs(id: container.id, since: nil, tail: 50, tty: details.tty) {
            lines.append(line)
        }
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.timestamp != nil })
        print("live:", details.name, details.restartPolicy, lines.count, "lines; first:", lines.first?.message ?? "")
    }

    /// Runs the local hello-world image with --rm: it prints, exits and removes itself.
    @Test func runsHelloWorldAndCleansUp() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let request = RunRequest(image: "hello-world", name: "coliui-live-run", ports: [], volumes: [], environment: [],
                                 restartPolicy: .no, autoRemove: true, pull: false)
        let id = try await repository.run(request)
        #expect(!id.isEmpty)
        print("live run:", id.prefix(12))
    }

    /// Read-only: parses the real ~/.colima/default/colima.yaml.
    @Test func readsTheDefaultProfileSettings() async throws {
        let runtime = ColimaCLIRuntime(runner: ProcessCommandRunner(), executable: "colima")
        let settings = try await runtime.settings(profile: "default")
        #expect(settings.cpus > 0)
        print("live profile:", settings)
    }

    /// Read-only: never prunes.
    @Test func readsDiskUsage() async throws {
        let usage = try await DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket)).diskUsage()
        #expect(usage.totalBytes > 0)
        print("live df:", PruneTarget.allCases.map {
            "\($0.rawValue) \(ByteFormat.short(usage.category($0).totalBytes)) (\(ByteFormat.short(usage.category($0).reclaimableBytes)) reclaimable, \(usage.category($0).reclaimableItems.count) items)"
        }.joined(separator: "; "))
    }

    /// Lists images, then re-pulls hello-world (already local, so nothing changes) through the streaming puller.
    @Test func listsImagesAndPullsHelloWorld() async throws {
        let images = try await DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket)).images()
        #expect(!images.isEmpty)
        var last: PullProgress?
        for try await progress in DockerImagePuller(socketPath: socket).pull("hello-world") { last = progress }
        #expect(last?.phase == .done)
        print("live images:", images.count, "rows;", images.prefix(3).map { "\($0.reference) \($0.shortID) \(ByteFormat.short($0.size))" }, "pull:", last?.title ?? "nil")
    }

    /// Read-only: lists volumes with their sizes and which containers mount them.
    @Test func listsVolumes() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let volumes = try await repository.volumes()
        let mounted = Set(try await repository.listContainers().flatMap(\.volumeNames))
        print("live volumes:", volumes.count, volumes.prefix(4).map { "\($0.name) \($0.composeProject ?? "-") \($0.size.map(ByteFormat.short) ?? "?") used=\(mounted.contains($0.name))" })
    }

    /// Read-only: lists networks and which containers are connected.
    @Test func listsNetworks() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let networks = try await repository.networks()
        let containers = try await repository.listContainers()
        #expect(networks.contains { $0.isBuiltIn })
        print("live networks:", networks.map { network in
            "\(network.name) \(network.driver) \(network.subnet ?? "-") [\(containers.filter { $0.networkNames.contains(network.name) }.count)]"
        })
    }

    /// Read-only: extended stats of a running container.
    @Test func readsExtendedStats() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let container = try #require(try await repository.listContainers().first { $0.isRunning })
        let stats = try await repository.stats(id: container.id)
        #expect(stats.sampledAt != nil)
        print("live stats:", container.name, stats.cpuDisplay, stats.memoryDisplay, "cpus", stats.onlineCPUs,
              "limit", stats.memoryLimit ?? -1, "net", stats.networkReceived, stats.networkSent, "blk", stats.blockRead, stats.blockWritten)
    }

    /// Parses a real `docker inspect` in Docker's key order; reads only.
    @Test func inspectsARunningContainer() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let container = try #require(try await repository.listContainers().first { $0.isRunning })
        let value = try await repository.inspect(id: container.id)
        guard case .object(let members) = value else { Issue.record("not an object"); return }
        #expect(members.first?.key == "Id")
        #expect(members.contains { $0.key == "Config" })
        #expect(try JSONValue.parse(Data(value.prettyPrinted().utf8)) == value)
        print("live inspect:", container.name, members.count, "keys")
    }

    /// Reads a running container's environment and its image's; reads only, prints no values.
    @Test func readsAContainersEnvironment() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let container = try #require(try await repository.listContainers().first { $0.isRunning })
        let variables = try await repository.environment(id: container.id)
        #expect(variables.contains { $0.name == "PATH" })
        print("live env:", container.name, variables.count, "vars,",
              variables.filter { $0.source == .image }.count, "from the image,", variables.filter(\.isSecret).count, "secret")
    }

    /// Lists /etc and reads /etc/hostname in every running container (GNU stat, BusyBox, distroless); reads only.
    @Test func browsesContainerFiles() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        for container in try await repository.listContainers().filter(\.isRunning) {
            do {
                let start = try await repository.workingDirectory(id: container.id)
                let files = try await repository.listFiles(id: container.id, path: "/etc")
                let hostname = String(decoding: try await repository.readFile(id: container.id, path: "/etc/hostname"), as: UTF8.self)
                #expect(files.contains { $0.name == "hostname" && $0.kind == .file })
                #expect(!hostname.isEmpty)
                print("live files:", container.name, "start", start, "·", files.count, "entries in /etc,",
                      files.filter { $0.kind == .symlink }.count, "links")
            } catch ContainerFilesError.noShell {
                print("live files:", container.name, "has no shell")
            }
        }
    }

    /// Opens /bin/sh in a running container, echoes, exits. Changes nothing.
    @Test func runsAnInteractiveShell() async throws {
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket))
        let container = try #require(try await repository.listContainers().first { $0.isRunning })
        let session = try await DockerShell(socketPath: socket)
            .openShell(containerID: container.id, shell: "/bin/sh", user: "", columns: 100, rows: 30)
        session.resize(columns: 120, rows: 40)
        session.send(Data("echo coliui-$((40+2))\nexit\n".utf8))
        var output = Data()
        for try await chunk in session.output { output.append(chunk) }
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("coliui-42"))
        print("live shell:", container.name, text.replacingOccurrences(of: "\r", with: "").suffix(80))
    }
}
