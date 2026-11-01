import ColiUICore
import Foundation
import Observation

enum ContainerFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case stopped = "Stopped"

    var id: Self { self }
}

enum ContainerAction {
    case start, stop, restart, remove
}

@MainActor
@Observable
final class ContainersViewModel {
    private(set) var containers: [Container] = []
    private(set) var busyIDs: Set<String> = []
    private(set) var hasLoaded = false
    var errorMessage: String?
    var filter: ContainerFilter = .all
    var searchText = ""
    var selection: Container.ID?
    /// Set to ask for confirmation before removing.
    var pendingRemoval: Container?

    private let repository: ContainerRepository

    init(repository: ContainerRepository) {
        self.repository = repository
    }

    var runningCount: Int { containers.filter(\.isRunning).count }
    var stoppedCount: Int { containers.count - runningCount }

    func count(for filter: ContainerFilter) -> Int {
        switch filter {
        case .all: containers.count
        case .running: runningCount
        case .stopped: stoppedCount
        }
    }

    var visibleContainers: [Container] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return containers.filter { container in
            let matchesFilter = switch filter {
            case .all: true
            case .running: container.isRunning
            case .stopped: !container.isRunning
            }
            guard matchesFilter else { return false }
            return query.isEmpty
                || container.name.localizedCaseInsensitiveContains(query)
                || container.image.localizedCaseInsensitiveContains(query)
        }
    }

    func refresh() async {
        do {
            containers = try await repository.listContainers()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            // A stale list would suggest containers are still there while Docker is down.
            containers = []
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    func perform(_ action: ContainerAction, on container: Container) async {
        busyIDs.insert(container.id)
        defer { busyIDs.remove(container.id) }
        do {
            switch action {
            case .start: try await repository.start(id: container.id)
            case .stop: try await repository.stop(id: container.id)
            case .restart: try await repository.restart(id: container.id)
            case .remove: try await repository.remove(id: container.id, force: container.isRunning)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
    }
}
