import ColiUICore
import Foundation
import Observation

/// Composition root: wires adapters into view models and keeps them fresh.
@MainActor
@Observable
final class AppModel {
    let containers: ContainersViewModel
    let colima: ColimaViewModel
    var section: SidebarSection? = .containers
    private(set) var summary: DockerSummary?

    private let inventory: DockerInventory?
    private var pollTask: Task<Void, Never>?

    static let shared = AppModel.live()

    init(containers: ContainersViewModel, colima: ColimaViewModel, inventory: DockerInventory? = nil) {
        self.containers = containers
        self.colima = colima
        self.inventory = inventory
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
            inventory: repository
        )
    }

    /// Polls containers every 3 s; Colima and sidebar totals every 15 s (each `colima list` spawns processes).
    /// Replace with the Docker events stream later.
    func startPolling() {
        guard pollTask == nil else { return }
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
}
