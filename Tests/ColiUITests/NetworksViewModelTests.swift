import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeNetworkRepository: NetworkRepository, @unchecked Sendable {
    struct Created: Equatable { let name: String; let driver: String; let `internal`: Bool }
    private let lock = NSLock()
    private var _removed: [String] = []
    private var _created: [Created] = []
    private var _loads = 0
    var networks: [DockerNetwork]
    var error: Error?

    init(networks: [DockerNetwork]) { self.networks = networks }

    var removed: [String] { lock.withLock { _removed } }
    var created: [Created] { lock.withLock { _created } }
    var loads: Int { lock.withLock { _loads } }

    func networks() async throws -> [DockerNetwork] {
        lock.withLock { _loads += 1 }
        return networks
    }

    func createNetwork(name: String, driver: String, internal: Bool) async throws {
        if let error { throw error }
        lock.withLock { _created.append(Created(name: name, driver: driver, internal: `internal`)) }
    }

    func removeNetwork(id: String) async throws {
        if let error { throw error }
        lock.withLock { _removed.append(id) }
    }
}

private func network(_ id: String, _ name: String, driver: String = "bridge", project: String? = nil, subnet: String? = nil) -> DockerNetwork {
    DockerNetwork(id: id, name: name, driver: driver, subnet: subnet, gateway: nil, composeProject: project, isInternal: false)
}

private let shop = network("n1", "shop_default", project: "shop", subnet: "172.19.0.0/16")
private let legacy = network("n2", "legacy_default", project: "legacy")
private let bridge = network("n3", "bridge", subnet: "172.17.0.0/16")
private let host = network("n4", "host", driver: "host")

private let api = Container(id: "c1", name: "api-server", image: "api", state: .running, status: "Up", networkNames: ["shop_default"])
private let db = Container(id: "c2", name: "postgres-dev", image: "pg", state: .running, status: "Up", networkNames: ["shop_default"])
private let mail = Container(id: "c3", name: "mailpit", image: "mail", state: .exited, status: "Exited", networkNames: ["bridge"])

@MainActor
private func makeModel(networks: [DockerNetwork] = [shop, legacy, bridge, host]) -> (NetworksViewModel, FakeNetworkRepository) {
    let repository = FakeNetworkRepository(networks: networks)
    return (NetworksViewModel(repository: repository, containers: { [api, db, mail] }, toastDuration: .zero), repository)
}

@MainActor
@Suite struct NetworksViewModelTests {
    @Test func summarisesAndCountsUse() async {
        let (model, _) = makeModel()
        await model.refresh()

        #expect(model.summary == "4 networks · 2 in use")
        #expect(model.count(for: .used) == 2)
        #expect(model.count(for: .unused) == 2)
        #expect(model.connected(shop) == ["api-server", "postgres-dev"])
        #expect(!model.canRemove(shop))
        #expect(!model.canRemove(host))
        #expect(model.canRemove(legacy))
    }

    @Test func sortsFiltersAndSearches() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.visibleNetworks.map(\.name) == ["bridge", "host", "legacy_default", "shop_default"])
        model.sort = .containers
        #expect(model.visibleNetworks.map(\.name) == ["shop_default", "bridge", "host", "legacy_default"])
        model.filter = .unused
        #expect(model.visibleNetworks.map(\.name) == ["host", "legacy_default"])
        model.filter = .all
        model.searchText = "172.19"
        #expect(model.visibleNetworks == [shop])
    }

    @Test func removesByIDThenRefreshes() async {
        let (model, repository) = makeModel()
        await model.remove(legacy)
        #expect(repository.removed == ["n2"])
        #expect(repository.loads == 1)
        #expect(model.toast == "Removed legacy_default")
    }

    @Test func keepsTheRemoveError() async {
        let (model, repository) = makeModel()
        repository.error = DockerError.requestFailed(status: 403, message: "network has active endpoints")
        await model.remove(legacy)
        #expect(model.errorMessage == "network has active endpoints")
        #expect(repository.loads == 0)
    }

    @Test func createsWithDriverAndInternal() async {
        let (model, repository) = makeModel()
        model.openCreateBar()
        model.newName = " backend "
        model.newDriver = "macvlan"
        model.newInternal = true
        await model.create()

        #expect(repository.created == [.init(name: "backend", driver: "macvlan", internal: true)])
        #expect(!model.isCreateBarOpen)
        #expect(model.newName == "")
        #expect(model.newDriver == "bridge")
        #expect(!model.newInternal)
        #expect(model.toast == "Created backend")
    }

    @Test(arguments: ["", "-bad", "has space", "shop_default"])
    func rejectsInvalidOrTakenNames(name: String) async {
        let (model, repository) = makeModel()
        await model.refresh()
        model.openCreateBar()
        model.newName = name
        #expect(model.nameError != nil)
        await model.create()
        #expect(repository.created.isEmpty)
    }

    @Test func createErrorsStayInTheBar() async {
        let (model, repository) = makeModel()
        repository.error = DockerError.requestFailed(status: 400, message: "invalid subnet")
        model.openCreateBar()
        model.newName = "backend"
        await model.create()
        #expect(model.isCreateBarOpen)
        #expect(model.createError == "invalid subnet")
    }
}
