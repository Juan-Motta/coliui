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

/// `docker inspect` for one container, with secret-looking `Config.Env` values masked.
public protocol ContainerInspector: Sendable {
    func inspect(id: String) async throws -> JSONValue
}

public protocol DockerInventory: Sendable {
    func summary() async throws -> DockerSummary
}

public protocol ContainerRunner: Sendable {
    /// Pulls if asked (or if the image is missing), creates and starts the container; returns its ID.
    func run(_ request: RunRequest) async throws -> String
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

public protocol ImageRepository: Sendable {
    func images() async throws -> [DockerImage]
    /// Removes a tag (or an untagged image by ID); fails while a container uses it.
    func removeImage(_ reference: String) async throws
}

public protocol ImagePuller: Sendable {
    /// Streams overall progress until the image is pulled; cancelling stops the pull.
    func pull(_ reference: String) -> AsyncThrowingStream<PullProgress, Error>
}

public protocol VolumeRepository: Sendable {
    func volumes() async throws -> [DockerVolume]
    func createVolume(name: String) async throws
    /// Deletes the volume and its data; fails while a container uses it.
    func removeVolume(name: String) async throws
}

public protocol NetworkRepository: Sendable {
    func networks() async throws -> [DockerNetwork]
    func createNetwork(name: String, driver: String, internal: Bool) async throws
    /// Fails for built-in networks and while containers are connected.
    func removeNetwork(id: String) async throws
}

/// An interactive shell inside a container (`docker exec -it`).
public protocol ShellSession: AnyObject, Sendable {
    /// Raw TTY output; finishes when the shell exits or the session closes.
    var output: AsyncThrowingStream<Data, Error> { get }
    func send(_ data: Data)
    func resize(columns: Int, rows: Int)
    func close()
}

public protocol ShellConnector: Sendable {
    func openShell(containerID: String, shell: String, user: String, columns: Int, rows: Int) async throws -> ShellSession
}
