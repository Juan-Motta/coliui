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

    /// Read-only: never prunes.
    @Test func readsDiskUsage() async throws {
        let usage = try await DockerEngineRepository(transport: UnixSocketTransport(socketPath: socket)).diskUsage()
        #expect(usage.totalBytes > 0)
        print("live df:", PruneTarget.allCases.map {
            "\($0.rawValue) \(ByteFormat.short(usage.category($0).totalBytes)) (\(ByteFormat.short(usage.category($0).reclaimableBytes)) reclaimable, \(usage.category($0).reclaimableItems.count) items)"
        }.joined(separator: "; "))
    }
}
