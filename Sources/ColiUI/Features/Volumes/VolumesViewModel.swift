import ColiUICore
import Foundation
import Observation

enum VolumeFilter: String, CaseIterable {
    case all = "All"
    case used = "In use"
    case unused = "Unused"
}

enum VolumeSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case created = "Created"
    case size = "Size"

    var id: Self { self }
}

/// Volumes.dc.html: which containers mount each volume, the create bar.
@MainActor
@Observable
final class VolumesViewModel {
    private(set) var volumes: [DockerVolume] = []
    @ObservationIgnored private var refreshes = LatestRequest()
    private(set) var isLoading = false
    var filter: VolumeFilter = .all
    var sort: VolumeSort = .name
    var searchText = ""
    var errorMessage: String?
    /// Set to ask for confirmation before removing.
    var pendingRemoval: DockerVolume?
    private(set) var removingNames: Set<String> = []
    private(set) var toast: String?

    private(set) var isCreateBarOpen = false
    var newName = ""
    private(set) var isCreating = false
    private(set) var createError: String?

    private let repository: VolumeRepository
    /// The container list the app already polls; used to tell which volumes are mounted.
    private let containers: @MainActor () -> [Container]
    private let toastDuration: Duration
    private var toastTask: Task<Void, Never>?

    init(
        repository: VolumeRepository,
        containers: @escaping @MainActor () -> [Container],
        toastDuration: Duration = .seconds(2)
    ) {
        self.repository = repository
        self.containers = containers
        self.toastDuration = toastDuration
    }

    // MARK: Derived

    var summary: String {
        let size = volumes.reduce(0) { $0 + ($1.size ?? 0) }
        return "\(volumes.count) volume\(volumes.count == 1 ? "" : "s") · \(ByteFormat.short(size))"
    }

    func usedBy(_ volume: DockerVolume) -> [String] {
        containers()
            .filter { $0.volumeNames.contains(volume.name) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func canRemove(_ volume: DockerVolume) -> Bool {
        usedBy(volume).isEmpty
    }

    func count(for filter: VolumeFilter) -> Int {
        volumes.filter { matches($0, filter) }.count
    }

    var visibleVolumes: [DockerVolume] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return volumes
            .filter { matches($0, filter) }
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.composeProject?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { lhs, rhs in
                switch sort {
                case .created where lhs.created != rhs.created:
                    (lhs.created ?? .distantPast) > (rhs.created ?? .distantPast)
                case .size where lhs.size != rhs.size:
                    (lhs.size ?? -1) > (rhs.size ?? -1)
                default:
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private func matches(_ volume: DockerVolume, _ filter: VolumeFilter) -> Bool {
        switch filter {
        case .all: true
        case .used: !canRemove(volume)
        case .unused: canRemove(volume)
        }
    }

    /// Same rule as `docker volume create`: starts with a letter or digit, then letters, digits, "_", "." or "-".
    var nameError: String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Enter a name." }
        if name.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"#, options: .regularExpression) == nil {
            return "Names can use letters, digits, “_”, “.” and “-”, and must start with a letter or digit."
        }
        if volumes.contains(where: { $0.name == name }) { return "A volume named “\(name)” already exists." }
        return nil
    }

    // MARK: Actions

    func refresh() async {
        isLoading = true
        let request = refreshes.next()
        do {
            let list = try await repository.volumes()
            guard refreshes.isLatest(request) else { return }
            volumes = list
            errorMessage = nil
        } catch {
            guard refreshes.isLatest(request) else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func remove(_ volume: DockerVolume) async {
        removingNames.insert(volume.name)
        defer { removingNames.remove(volume.name) }
        do {
            try await repository.removeVolume(name: volume.name)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
        showToast("Removed \(volume.name)")
    }

    func openCreateBar() {
        isCreateBarOpen = true
        createError = nil
    }

    func closeCreateBar() {
        isCreateBarOpen = false
        createError = nil
    }

    func create() async {
        guard nameError == nil, !isCreating else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        isCreating = true
        defer { isCreating = false }
        do {
            try await repository.createVolume(name: name)
        } catch {
            createError = error.localizedDescription
            return
        }
        isCreateBarOpen = false
        createError = nil
        newName = ""
        showToast("Created \(name)")
        await refresh()
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        let duration = toastDuration
        guard duration > .zero else { return }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
