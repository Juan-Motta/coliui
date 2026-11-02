import ColiUICore
import Foundation
import Observation

/// Composition root: wires adapters into view models and keeps them fresh.
@MainActor
@Observable
final class AppModel {
    let containers: ContainersViewModel
    let colima: ColimaViewModel
    let cleanup: CleanupViewModel
    let profiles: ProfilesViewModel
    var section: SidebarSection? = .containers
    private(set) var summary: DockerSummary?
    /// The open container detail, if any (shown in place of the list).
    private(set) var detail: ContainerDetailViewModel?
    /// The "Run a new container" sheet, while open.
    private(set) var runForm: RunContainerViewModel?

    private let repository: ContainerRepository?
    private let runner: ContainerRunner?
    private let logSource: ContainerLogSource?
    private let inventory: DockerInventory?
    private let events: (@Sendable () -> AsyncThrowingStream<Void, Error>)?
    private var pollTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?

    static let shared = AppModel.live()

    init(
        containers: ContainersViewModel,
        colima: ColimaViewModel,
        cleanup: CleanupViewModel,
        profiles: ProfilesViewModel,
        repository: ContainerRepository? = nil,
        runner: ContainerRunner? = nil,
        logSource: ContainerLogSource? = nil,
        inventory: DockerInventory? = nil,
        events: (@Sendable () -> AsyncThrowingStream<Void, Error>)? = nil
    ) {
        self.containers = containers
        self.colima = colima
        self.cleanup = cleanup
        self.profiles = profiles
        self.repository = repository
        self.runner = runner
        self.logSource = logSource
        self.inventory = inventory
        self.events = events
    }

    func openDetail(_ container: Container) {
        guard let repository, let logSource else { return }
        detail?.stop()
        // A stopped container's last lines are usually older than 15 minutes.
        let detail = ContainerDetailViewModel(
            containerID: container.id,
            repository: repository,
            logSource: logSource,
            range: container.isRunning ? .fifteenMinutes : .all
        )
        self.detail = detail
        Task { await detail.start() }
    }

    func openRunForm() {
        guard let runner, runForm == nil else { return }
        runForm = RunContainerViewModel(runner: runner)
    }

    func closeRunForm() {
        runForm = nil
    }

    func submitRunForm() async {
        guard let form = runForm, let started = await form.run() else { return }
        runForm = nil
        await containers.refresh()
        containers.showToast("Started \(started)")
    }

    func closeDetail() {
        detail?.stop()
        detail = nil
    }

    func select(_ section: SidebarSection) {
        closeDetail()
        self.section = section
        if section == .cleanup {
            Task { await cleanup.scan() }
        }
        if section == .profiles {
            Task { await profiles.load() }
        }
    }

    static func live(profile: String = "default") -> AppModel {
        let socketPath = DockerSocket.resolve(
            environment: ProcessInfo.processInfo.environment,
            home: NSHomeDirectory(),
            profile: profile
        )
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socketPath))
        let runtime: ColimaRuntime = ColimaCLIRuntime.locateExecutable()
            .map { ColimaCLIRuntime(runner: ProcessCommandRunner(), executable: $0) }
            ?? UnavailableColimaRuntime()
        return AppModel(
            containers: ContainersViewModel(repository: repository),
            colima: ColimaViewModel(runtime: runtime, profile: profile),
            cleanup: CleanupViewModel(maintenance: repository),
            profiles: ProfilesViewModel(runtime: runtime, activeProfile: profile),
            repository: repository,
            runner: repository,
            logSource: DockerLogStream(socketPath: socketPath),
            inventory: repository,
            events: { DockerEvents.containerEvents(socketPath: socketPath) }
        )
    }

    /// Refreshes the list as soon as Docker reports a container event; reconnects after 5 s if the stream drops.
    private func startEvents() {
        guard eventsTask == nil, let events else { return }
        eventsTask = Task {
            while !Task.isCancelled {
                do {
                    for try await _ in events() { await containers.refresh() }
                } catch {}
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Polls containers every 3 s; Colima and sidebar totals every 15 s (each `colima list` spawns processes).
    /// Replace with the Docker events stream later.
    func startPolling() {
        startEvents()
        guard pollTask == nil else { return }
        // `docker system df` takes about a second, so measure once at launch and on demand.
        Task { await cleanup.scan() }
        pollTask = Task {
            var tick = 0
            while !Task.isCancelled {
                if tick % 5 == 0 {
                    await colima.refresh()
                    summary = try? await inventory?.summary()
                }
                await containers.refresh()
                tick += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func performColima(_ action: ColimaAction) async {
        await colima.perform(action)
        await containers.refresh()
    }
}

private struct UnavailableColimaRuntime: ColimaRuntime {
    func instances() async throws -> [ColimaInstance] { throw ColimaError.notInstalled }
    func start(profile: String) async throws { throw ColimaError.notInstalled }
    func stop(profile: String) async throws { throw ColimaError.notInstalled }
    func restart(profile: String) async throws { throw ColimaError.notInstalled }
    func settings(profile: String) async throws -> ColimaProfileSettings { throw ColimaError.notInstalled }
    func apply(_ settings: ColimaProfileSettings, to profile: String, isRunning: Bool) async throws { throw ColimaError.notInstalled }
    func create(profile: String, settings: ColimaProfileSettings) async throws { throw ColimaError.notInstalled }
    func delete(profile: String) async throws { throw ColimaError.notInstalled }
}
