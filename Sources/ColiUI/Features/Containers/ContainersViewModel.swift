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

    /// Compose projects by name (members by service), then the standalone containers.
    static func grouped(_ containers: [Container], standaloneName: String) -> [ComposeGroup] {
        let byProject = Dictionary(grouping: containers.filter { $0.composeProject != nil }) { $0.composeProject! }
        var groups = byProject.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { project in
            let members = byProject[project]!.sorted {
                ($0.composeService ?? $0.name).localizedStandardCompare($1.composeService ?? $1.name) == .orderedAscending
            }
            return ComposeGroup(id: project, name: project, configFile: members.first?.composeConfigFile, containers: members)
        }
        let standalone = containers.filter { $0.composeProject == nil }
        if !standalone.isEmpty {
            groups.append(ComposeGroup(id: standaloneID, name: standaloneName, configFile: nil, containers: standalone))
        }
        return groups
    }
}

@MainActor
@Observable
final class ContainersViewModel {
    private(set) var containers: [Container] = []
    @ObservationIgnored private var refreshes = LatestRequest()
    /// The Search field has focus, so text-editing keys (⌘⌫) belong to it.
    var isSearchFocused = false
    /// CPU / memory for running containers, keyed by container ID.
    private(set) var stats: [String: ContainerStats] = [:]
    private(set) var busyIDs: Set<String> = []
    private(set) var hasLoaded = false
    var errorMessage: String?
    var filter: ContainerFilter = .all
    var sort: ContainerSort = .name
    var searchText = ""
    var viewMode: ContainerViewMode = .compose
    /// Keyboard selection (↑/↓); Space, ⌘L, ⌘O and ⌘⌫ act on it.
    var selectedID: Container.ID?
    /// Set to ask for confirmation before removing.
    var pendingRemoval: Container?
    private(set) var collapsedGroups: Set<String> = []
    var toast: String? { toasts.message }

    /// Called with every fresh list (Settings › Notifications watches state changes).
    var onRefresh: (([Container]) -> Void)?

    private let repository: ContainerRepository
    private let toasts: Toast

    init(repository: ContainerRepository, toastDuration: Duration = .seconds(2)) {
        self.repository = repository
        toasts = Toast(duration: toastDuration)
    }

    /// Compose projects by name, then standalone containers. Search applies; the state filter
    /// belongs to the list view and doesn't.
    var composeGroups: [ComposeGroup] {
        ComposeGroup.grouped(containers.filter(matchesSearch), standaloneName: "Standalone containers")
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
        toasts.show(message)
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
        let ordered = sort == .name ? containers : containers.filter(\.isRunning) + containers.filter { !$0.isRunning }
        return ordered.filter { container in
            let matchesFilter = switch filter {
            case .all: true
            case .running: container.isRunning
            case .stopped: !container.isRunning
            }
            return matchesFilter && matchesSearch(container)
        }
    }

    func refresh() async {
        let request = refreshes.next()
        do {
            let list = try await repository.listContainers()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard refreshes.isLatest(request) else { return }
            containers = list
            errorMessage = nil
            if let selectedID, !containers.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            onRefresh?(containers)
        } catch {
            guard refreshes.isLatest(request) else { return }
            // A stale list would suggest containers are still there while Docker is down.
            containers = []
            stats = [:]
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    /// Each stats call takes ~1 s (the engine samples twice), so query running containers in parallel.
    func refreshStats() async {
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

    // MARK: Selection

    /// Rows in on-screen order: the filtered list, or the expanded Compose groups.
    var navigationOrder: [Container] {
        switch viewMode {
        case .list: visibleContainers
        case .compose: composeGroups.filter { !collapsedGroups.contains($0.id) }.flatMap(\.containers)
        }
    }

    var selectedContainer: Container? {
        selectedID.flatMap { id in containers.first { $0.id == id } }
    }

    func selectNext() { moveSelection(by: 1) }
    func selectPrevious() { moveSelection(by: -1) }

    private func moveSelection(by step: Int) {
        let order = navigationOrder
        guard !order.isEmpty else { return }
        guard let current = order.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = step > 0 ? order.first?.id : order.last?.id
            return
        }
        selectedID = order[min(max(current + step, 0), order.count - 1)].id
    }

    func toggleSelected() async {
        guard let container = selectedContainer else { return }
        await perform(container.isRunning ? .stop : .start, on: container)
    }

    func requestRemoveSelected() {
        pendingRemoval = selectedContainer
    }

    var selectedPortURL: URL? {
        selectedContainer?.ports.lazy.compactMap(\.localURL).first
    }

    /// Settings › Refresh stats every › Off: CPU and memory show "—".
    func clearStats() {
        stats = [:]
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
