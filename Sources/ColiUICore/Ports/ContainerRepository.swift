import Foundation

public protocol ContainerRepository: Sendable {
    func listContainers() async throws -> [Container]
    func details(id: String) async throws -> ContainerDetails
    func stats(id: String) async throws -> ContainerStats
    func start(id: String) async throws
    func stop(id: String) async throws
    func restart(id: String) async throws
    func remove(id: String, force: Bool) async throws
}

public protocol DockerInventory: Sendable {
    func summary() async throws -> DockerSummary
}

public protocol DockerMaintenance: Sendable {
    func diskUsage() async throws -> DiskUsage
    /// Removes what `target` no longer uses and returns the bytes freed.
    func prune(_ target: PruneTarget) async throws -> Int64
}

public protocol ContainerLogSource: Sendable {
    /// Streams log lines, starting with the last `tail` lines since `since`, until cancelled.
    func logs(id: String, since: Date?, tail: Int, tty: Bool) -> AsyncThrowingStream<LogLine, Error>
}
