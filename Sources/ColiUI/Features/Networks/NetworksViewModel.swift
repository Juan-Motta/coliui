import ColiUICore
import Foundation
import Observation

enum NetworkFilter: String, CaseIterable {
    case all = "All"
    case used = "In use"
    case unused = "Unused"
}

enum NetworkSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case containers = "Containers"

    var id: Self { self }
}

/// Networks.dc.html: which containers are connected to each network, the create bar.
@MainActor
@Observable
final class NetworksViewModel {
    static let drivers = ["bridge", "macvlan"]

    private(set) var networks: [DockerNetwork] = []
    @ObservationIgnored private var refreshes = LatestRequest()
    private(set) var isLoading = false
    var filter: NetworkFilter = .all
    var sort: NetworkSort = .name
    var searchText = ""
    var errorMessage: String?
    /// Set to ask for confirmation before removing.
    var pendingRemoval: DockerNetwork?
    private(set) var removingIDs: Set<String> = []
    var toast: String? { toasts.message }

    private(set) var isCreateBarOpen = false
    var newName = ""
    var newDriver = "bridge"
    var newInternal = false
    private(set) var isCreating = false
    private(set) var createError: String?

    private let repository: NetworkRepository
    /// The container list the app already polls; used to tell which networks have containers.
    private let containers: @MainActor () -> [Container]
    private let toasts: Toast

    init(
        repository: NetworkRepository,
        containers: @escaping @MainActor () -> [Container],
        toastDuration: Duration = .seconds(2)
    ) {
        self.repository = repository
        self.containers = containers
        toasts = Toast(duration: toastDuration)
    }

    // MARK: Derived

    var summary: String {
        "\(networks.count) network\(networks.count == 1 ? "" : "s") · \(count(for: .used)) in use"
    }

    @ObservationIgnored private var usage = ContainerUsageIndex { $0.networkNames }

    func connected(_ network: DockerNetwork) -> [String] {
        usage.names(for: network.name, in: containers())
    }

    func canRemove(_ network: DockerNetwork) -> Bool {
        !network.isBuiltIn && connected(network).isEmpty
    }

    func count(for filter: NetworkFilter) -> Int {
        networks.filter { matches($0, filter) }.count
    }

    var visibleNetworks: [DockerNetwork] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let counts = Dictionary(uniqueKeysWithValues: networks.map { ($0.id, connected($0).count) })
        return networks
            .filter { matches($0, filter) }
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.driver.localizedCaseInsensitiveContains(query)
                    || ($0.subnet?.contains(query) ?? false)
                    || ($0.composeProject?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { lhs, rhs in
                if sort == .containers, counts[lhs.id] != counts[rhs.id] {
                    return counts[lhs.id, default: 0] > counts[rhs.id, default: 0]
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func matches(_ network: DockerNetwork, _ filter: NetworkFilter) -> Bool {
        switch filter {
        case .all: true
        case .used: !connected(network).isEmpty
        case .unused: connected(network).isEmpty
        }
    }

    /// Same rule as `docker network create`: starts with a letter or digit, then letters, digits, "_", "." or "-".
    var nameError: String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Enter a name." }
        if let error = DockerName.formatError(name) { return error }
        if networks.contains(where: { $0.name == name }) { return "A network named “\(name)” already exists." }
        return nil
    }

    // MARK: Actions

    func refresh() async {
        isLoading = true
        let request = refreshes.next()
        do {
            let list = try await repository.networks()
            guard refreshes.isLatest(request) else { return }
            networks = list
            errorMessage = nil
        } catch {
            guard refreshes.isLatest(request) else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func remove(_ network: DockerNetwork) async {
        removingIDs.insert(network.id)
        defer { removingIDs.remove(network.id) }
        do {
            try await repository.removeNetwork(id: network.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
        showToast("Removed \(network.name)")
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
            try await repository.createNetwork(name: name, driver: newDriver, internal: newInternal)
        } catch {
            createError = error.localizedDescription
            return
        }
        isCreateBarOpen = false
        createError = nil
        newName = ""
        newDriver = "bridge"
        newInternal = false
        showToast("Created \(name)")
        await refresh()
    }

    func showToast(_ message: String) {
        toasts.show(message)
    }
}
