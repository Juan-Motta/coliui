import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeContainerRepository: ContainerRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _containers: [Container]
    private var _actions: [String] = []
    var listError: Error?
    var actionError: Error?

    init(_ containers: [Container]) { _containers = containers }

    var actions: [String] { lock.withLock { _actions } }

    func setContainers(_ containers: [Container]) { lock.withLock { _containers = containers } }

    func listContainers() async throws -> [Container] {
        if let listError { throw listError }
        return lock.withLock { _containers }
    }

    private func record(_ action: String) throws {
        lock.withLock { _actions.append(action) }
        if let actionError { throw actionError }
    }

    func details(id: String) async throws -> ContainerDetails {
        ContainerDetails(
            id: id, name: "api-server", image: "myapp/api:latest", created: nil, restartPolicy: "no",
            network: "bridge", ipAddress: "172.17.0.4", mounts: [], environment: [], tty: false
        )
    }

    func stats(id: String) async throws -> ContainerStats {
        lock.withLock { _actions.append("stats \(id)") }
        return ContainerStats(cpuPercent: 1.5, memoryBytes: 1_048_576)
    }

    func start(id: String) async throws { try record("start \(id)") }
    func stop(id: String) async throws { try record("stop \(id)") }
    func restart(id: String) async throws { try record("restart \(id)") }
    func remove(id: String, force: Bool) async throws { try record("remove \(id) force=\(force)") }
}

private let sample = [
    Container(id: "c3", name: "worker", image: "myapp/worker", state: .exited, status: "Exited (1)"),
    Container(id: "c1", name: "api-server", image: "myapp/api:latest", state: .running, status: "Up 12 minutes"),
    Container(id: "c2", name: "postgres", image: "postgres:16-alpine", state: .running, status: "Up 3 hours"),
]

@MainActor
@Suite struct ContainersViewModelTests {
    @Test func refreshLoadsContainersSortedByName() async {
        let model = ContainersViewModel(repository: FakeContainerRepository(sample))
        await model.refresh()
        #expect(model.containers.map(\.name) == ["api-server", "postgres", "worker"])
        #expect(model.runningCount == 2)
        #expect(model.stoppedCount == 1)
        #expect(model.errorMessage == nil)
        #expect(model.hasLoaded)
    }

    @Test func filterAndSearchNarrowVisibleContainers() async {
        let model = ContainersViewModel(repository: FakeContainerRepository(sample))
        await model.refresh()

        model.filter = .running
        #expect(model.visibleContainers.map(\.name) == ["api-server", "postgres"])
        model.filter = .stopped
        #expect(model.visibleContainers.map(\.name) == ["worker"])

        model.filter = .all
        model.searchText = "POSTGRES"
        #expect(model.visibleContainers.map(\.name) == ["postgres"])
        model.searchText = "myapp"
        #expect(model.visibleContainers.map(\.name) == ["api-server", "worker"])
    }

    @Test func statsAreLoadedForRunningContainersOnly() async {
        let repository = FakeContainerRepository(sample)
        let model = ContainersViewModel(repository: repository)
        await model.refresh()
        // Stats follow their own interval (Settings › Refresh stats every), not the list refresh.
        #expect(repository.actions.isEmpty)
        await model.refreshStats()

        #expect(Set(repository.actions) == ["stats c1", "stats c2"])
        #expect(model.stats["c1"]?.cpuDisplay == "1.5%")
        #expect(model.stats["c3"] == nil)
        model.clearStats()
        #expect(model.stats.isEmpty)
    }

    @Test func sortByStatusPutsRunningFirst() async {
        let model = ContainersViewModel(repository: FakeContainerRepository([
            Container(id: "a", name: "alpha", image: "x", state: .exited, status: "Exited (0)"),
            Container(id: "z", name: "zulu", image: "x", state: .running, status: "Up"),
        ]))
        await model.refresh()
        #expect(model.visibleContainers.map(\.name) == ["alpha", "zulu"])
        model.sort = .status
        #expect(model.visibleContainers.map(\.name) == ["zulu", "alpha"])
    }

    @Test func actionCallsRepositoryThenRefreshes() async {
        let repository = FakeContainerRepository(sample)
        let model = ContainersViewModel(repository: repository)
        await model.refresh()

        repository.setContainers([])
        await model.perform(.stop, on: sample[1])

        #expect(repository.actions.filter { !$0.hasPrefix("stats") } == ["stop c1"])
        #expect(model.containers.isEmpty)
        #expect(model.busyIDs.isEmpty)
    }

    @Test func removeForcesRunningContainers() async {
        let repository = FakeContainerRepository(sample)
        let model = ContainersViewModel(repository: repository)
        await model.perform(.remove, on: sample[1])
        await model.perform(.remove, on: sample[0])
        #expect(repository.actions.filter { !$0.hasPrefix("stats") } == ["remove c1 force=true", "remove c3 force=false"])
    }

    @Test func listFailureSetsErrorMessage() async {
        let repository = FakeContainerRepository(sample)
        repository.listError = DockerError.socketUnavailable(path: "/x.sock")
        let model = ContainersViewModel(repository: repository)
        await model.refresh()
        #expect(model.errorMessage == "Docker isn't reachable at /x.sock. Is Colima running?")
        #expect(model.containers.isEmpty)
    }

    @Test func actionFailureKeepsErrorVisible() async {
        let repository = FakeContainerRepository(sample)
        repository.actionError = DockerError.requestFailed(status: 409, message: "conflict")
        let model = ContainersViewModel(repository: repository)
        await model.perform(.start, on: sample[0])
        #expect(model.errorMessage == "conflict")
    }
}

final class FakeColimaRuntime: ColimaRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [String] = []
    var instancesResult: [ColimaInstance]
    var error: Error?

    init(_ instances: [ColimaInstance]) { instancesResult = instances }

    var commands: [String] { lock.withLock { _commands } }

    func instances() async throws -> [ColimaInstance] {
        if let error { throw error }
        return instancesResult
    }

    func start(profile: String) async throws { lock.withLock { _commands.append("start \(profile)") } }
    func stop(profile: String) async throws { lock.withLock { _commands.append("stop \(profile)") } }
    func restart(profile: String) async throws { lock.withLock { _commands.append("restart \(profile)") } }

    var settingsByProfile: [String: ColimaProfileSettings] = [:]
    var commandError: Error?

    func settings(profile: String) async throws -> ColimaProfileSettings {
        guard let settings = settingsByProfile[profile] else { throw ColimaError.unexpectedOutput }
        return settings
    }

    func apply(_ settings: ColimaProfileSettings, to profile: String, isRunning: Bool) async throws {
        lock.withLock { _commands.append("apply \(profile) cpus=\(settings.cpus) running=\(isRunning)") }
        if let commandError { throw commandError }
    }

    func create(profile: String, settings: ColimaProfileSettings) async throws {
        lock.withLock { _commands.append("create \(profile) \(settings.vmType)") }
        if let commandError { throw commandError }
    }

    func delete(profile: String) async throws {
        lock.withLock { _commands.append("delete \(profile)") }
        if let commandError { throw commandError }
    }
}

@MainActor
@Suite struct ColimaViewModelTests {
    static let instances = [
        ColimaInstance(name: "work", status: .stopped, arch: "x86_64", cpus: 2, memoryBytes: 2 << 30, diskBytes: 60 << 30, runtime: "docker"),
        ColimaInstance(name: "default", status: .running, arch: "aarch64", cpus: 4, memoryBytes: 4 << 30, diskBytes: 100 << 30, runtime: "docker"),
    ]

    @Test func picksConfiguredProfile() async {
        let model = ColimaViewModel(runtime: FakeColimaRuntime(Self.instances), profile: "default")
        await model.refresh()
        #expect(model.instance?.name == "default")
        #expect(model.instance?.isRunning == true)
    }

    @Test func lifecycleCommandsUseProfileAndRefresh() async {
        let runtime = FakeColimaRuntime(Self.instances)
        let model = ColimaViewModel(runtime: runtime, profile: "default")
        await model.perform(.stop)
        await model.perform(.start)
        #expect(runtime.commands == ["stop default", "start default"])
        #expect(model.instance?.name == "default")
        #expect(model.isBusy == false)
    }

    @Test func missingProfileReportsNotFound() async {
        let model = ColimaViewModel(runtime: FakeColimaRuntime([]), profile: "default")
        await model.refresh()
        #expect(model.instance == nil)
        #expect(model.errorMessage == "Colima profile “default” not found. Start it with `colima start`.")
    }
}
