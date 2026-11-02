import ColiUICore
import Foundation
import Observation

enum ContainerFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case stopped = "Stopped"

    var id: Self { self }
}

enum ContainerViewMode: String, CaseIterable, Identifiable {
    case list = "List"
    case compose = "Compose groups"

    var id: Self { self }
}

enum ContainerSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case status = "Status"

    var id: Self { self }
}

enum ContainerAction {
    case start, stop, restart, remove
}

enum GroupAction {
    case stopAll, startAll, restart
}

/// Containers of one Compose project, or the standalone ones.
struct ComposeGroup: Identifiable {
    static let standaloneID = "standalone"

    let id: String
    let name: String
    let configFile: String?
    let containers: [Container]

    var isStandalone: Bool { id == Self.standaloneID }
    var runningCount: Int { containers.filter(\.isRunning).count }
}

@MainActor
@Observable
final class ContainersViewModel {
    private(set) var containers: [Container] = []
    /// CPU / memory for running containers, keyed by container ID.
    private(set) var stats: [String: ContainerStats] = [:]
    private(set) var busyIDs: Set<String> = []
    private(set) var hasLoaded = false
    var errorMessage: String?
    var filter: ContainerFilter = .all
    var sort: ContainerSort = .name
    var searchText = ""
    var viewMode: ContainerViewMode = .compose
    var hoveredID: Container.ID?
    var showRunComingSoon = false
    /// Set to ask for confirmation before removing.
    var pendingRemoval: Container?
    private(set) var collapsedGroups: Set<String> = []
    private(set) var toast: String?

    private let repository: ContainerRepository
    private let toastDuration: Duration
    private var toastTask: Task<Void, Never>?

    init(repository: ContainerRepository, toastDuration: Duration = .seconds(2)) {
        self.repository = repository
        self.toastDuration = toastDuration
    }

    /// Compose projects by name, then standalone containers. Search applies; the state filter
    /// belongs to the list view and doesn't.
    var composeGroups: [ComposeGroup] {
        let matching = containers.filter(matchesSearch)
        let byProject = Dictionary(grouping: matching.filter { $0.composeProject != nil }) { $0.composeProject! }
        var groups = byProject.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { project in
            let members = byProject[project]!.sorted {
                ($0.composeService ?? $0.name).localizedStandardCompare($1.composeService ?? $1.name) == .orderedAscending
            }
            return ComposeGroup(id: project, name: project, configFile: members.first?.composeConfigFile, containers: members)
        }
        let standalone = matching.filter { $0.composeProject == nil }
        if !standalone.isEmpty {
            groups.append(ComposeGroup(id: ComposeGroup.standaloneID, name: "Standalone containers", configFile: nil, containers: standalone))
        }
        return groups
    }

    func toggleGroup(_ id: String) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }

    func perform(_ action: GroupAction, on group: ComposeGroup) async {
        let targets: [Container] = switch action {
        case .stopAll: group.containers.filter(\.isRunning)
        case .startAll: group.containers.filter { !$0.isRunning }
        case .restart: group.containers
        }
        targets.forEach { busyIDs.insert($0.id) }
        defer { targets.forEach { busyIDs.remove($0.id) } }
        let repository = repository
        let failures = await withTaskGroup(of: String?.self) { tasks in
            for container in targets {
                tasks.addTask {
                    do {
                        switch action {
                        case .stopAll: try await repository.stop(id: container.id)
                        case .startAll: try await repository.start(id: container.id)
                        case .restart: try await repository.restart(id: container.id)
                        }
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            var messages: [String] = []
            for await message in tasks {
                if let message { messages.append(message) }
            }
            return messages
        }
        await refresh()
        if let first = failures.first { errorMessage = first }
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        let duration = toastDuration
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func matchesSearch(_ container: Container) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty
            || container.name.localizedCaseInsensitiveContains(query)
            || container.image.localizedCaseInsensitiveContains(query)
            || (container.composeService?.localizedCaseInsensitiveContains(query) ?? false)
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
        let ordered = sort == .name ? containers : containers.filter(\.isRunning) + containers.filter { !$0.isRunning }
        return ordered.filter { container in
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
            stats = [:]
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        await refreshStats()
    }

    /// Each stats call takes ~1 s (the engine samples twice), so query running containers in parallel.
    private func refreshStats() async {
        let repository = repository
        let running = containers.filter(\.isRunning).map(\.id)
        stats = await withTaskGroup(of: (String, ContainerStats?).self) { group in
            for id in running {
                group.addTask { (id, try? await repository.stats(id: id)) }
            }
            var collected: [String: ContainerStats] = [:]
            for await (id, value) in group {
                if let value { collected[id] = value }
            }
            return collected
        }
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
