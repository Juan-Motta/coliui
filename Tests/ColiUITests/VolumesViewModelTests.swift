import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeVolumeRepository: VolumeRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _removed: [String] = []
    private var _created: [String] = []
    private var _loads = 0
    var volumes: [DockerVolume]
    var error: Error?

    init(volumes: [DockerVolume]) { self.volumes = volumes }

    var removed: [String] { lock.withLock { _removed } }
    var created: [String] { lock.withLock { _created } }
    var loads: Int { lock.withLock { _loads } }

    func volumes() async throws -> [DockerVolume] {
        lock.withLock { _loads += 1 }
        return volumes
    }

    func createVolume(name: String) async throws {
        if let error { throw error }
        lock.withLock { _created.append(name) }
    }

    func removeVolume(name: String) async throws {
        if let error { throw error }
        lock.withLock { _removed.append(name) }
    }
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func volume(_ name: String, project: String? = nil, age: TimeInterval?, size: Int64?) -> DockerVolume {
    DockerVolume(name: name, driver: "local", created: age.map { now.addingTimeInterval(-$0) }, size: size,
                 composeProject: project, isAnonymous: false)
}

private let pgdata = volume("shop_pgdata", project: "shop", age: 1_800_000, size: 612_000_000)
private let certs = volume("nginx-certs", age: 5_000_000, size: 64_000)
private let legacy = volume("legacy_mysql", project: "legacy", age: 13_000_000, size: 948_000_000)
private let unmeasured = volume("fresh", age: 60, size: nil)

private let postgres = Container(id: "a3f9", name: "postgres-dev", image: "postgres:16", state: .running,
                                 status: "Up", volumeNames: ["shop_pgdata"])
private let backup = Container(id: "b7c1", name: "pg-backup", image: "postgres:16", state: .exited,
                               status: "Exited (0)", volumeNames: ["shop_pgdata", "nginx-certs"])

@MainActor
private func makeModel(
    volumes: [DockerVolume] = [pgdata, certs, legacy, unmeasured],
    containers: [Container] = [postgres, backup]
) -> (VolumesViewModel, FakeVolumeRepository) {
    let repository = FakeVolumeRepository(volumes: volumes)
    return (VolumesViewModel(repository: repository, containers: { containers }, toastDuration: .zero), repository)
}

@MainActor
@Suite struct VolumesViewModelTests {
    @Test func summarisesAndCountsUse() async {
        let (model, _) = makeModel()
        await model.refresh()

        #expect(model.summary == "4 volumes · 1.6 GB")
        #expect(model.count(for: .all) == 4)
        #expect(model.count(for: .used) == 2)
        #expect(model.count(for: .unused) == 2)
        #expect(model.usedBy(pgdata) == ["pg-backup", "postgres-dev"])
        #expect(!model.canRemove(certs))
        #expect(model.canRemove(legacy))
    }

    @Test func sortsFiltersAndSearches() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.visibleVolumes.map(\.name) == ["fresh", "legacy_mysql", "nginx-certs", "shop_pgdata"])
        model.sort = .created
        #expect(model.visibleVolumes.map(\.name) == ["fresh", "shop_pgdata", "nginx-certs", "legacy_mysql"])
        model.sort = .size
        #expect(model.visibleVolumes.map(\.name) == ["legacy_mysql", "shop_pgdata", "nginx-certs", "fresh"])
        model.filter = .unused
        #expect(Set(model.visibleVolumes.map(\.name)) == ["legacy_mysql", "fresh"])
        model.filter = .all
        model.searchText = "SHOP"
        #expect(model.visibleVolumes == [pgdata])
    }

    @Test func removesThenRefreshes() async {
        let (model, repository) = makeModel()
        await model.remove(legacy)
        #expect(repository.removed == ["legacy_mysql"])
        #expect(repository.loads == 1)
        #expect(model.toast == "Removed legacy_mysql")
    }

    @Test func keepsTheRemoveError() async {
        let (model, repository) = makeModel()
        repository.error = DockerError.requestFailed(status: 409, message: "volume is in use")
        await model.remove(legacy)
        #expect(model.errorMessage == "volume is in use")
        #expect(repository.loads == 0)
    }

    @Test func createsAndClosesTheBar() async {
        let (model, repository) = makeModel()
        model.openCreateBar()
        model.newName = " minio-data "
        await model.create()

        #expect(repository.created == ["minio-data"])
        #expect(!model.isCreateBarOpen)
        #expect(model.newName == "")
        #expect(model.toast == "Created minio-data")
        #expect(repository.loads == 1)
    }

    @Test(arguments: ["", "-bad", "has space", "shop_pgdata"])
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
        repository.error = DockerError.requestFailed(status: 500, message: "driver failed")
        model.openCreateBar()
        model.newName = "minio-data"
        await model.create()
        #expect(model.isCreateBarOpen)
        #expect(model.createError == "driver failed")

        model.closeCreateBar()
        #expect(!model.isCreateBarOpen)
        #expect(model.createError == nil)
    }
}
