import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeMaintenance: DockerMaintenance, @unchecked Sendable {
    private let lock = NSLock()
    private var _pruned: [PruneTarget] = []
    private var _scans = 0
    var usage: DiskUsage
    var pruneError: Error?

    init(usage: DiskUsage) { self.usage = usage }

    var pruned: [PruneTarget] { lock.withLock { _pruned } }
    var scans: Int { lock.withLock { _scans } }

    func diskUsage() async throws -> DiskUsage {
        lock.withLock { _scans += 1 }
        return usage
    }

    func prune(_ target: PruneTarget) async throws -> Int64 {
        if let pruneError { throw pruneError }
        lock.withLock { _pruned.append(target) }
        return usage.category(target).reclaimableBytes
    }
}

private func category(_ total: Int64, _ reclaimable: Int64, _ items: [String] = []) -> DiskCategory {
    DiskCategory(totalBytes: total, reclaimableBytes: reclaimable, reclaimableItems: items)
}

private let usage = DiskUsage(
    images: category(10_000, 3_400, ["old/tool:1.0"]),
    containers: category(500, 120, ["worker"]),
    volumes: category(2_000, 1_100, ["orphan"]),
    buildCache: category(7_000, 6_800, ["x1"])
)

@MainActor
@Suite struct CleanupViewModelTests {
    @Test func scanLoadsUsageAndStampsTheTime() async {
        let now = Date(timeIntervalSince1970: 1_793_600_000)
        let model = CleanupViewModel(maintenance: FakeMaintenance(usage: usage), now: { now })
        await model.scan()
        #expect(model.usage == usage)
        #expect(model.lastScan == now)
        #expect(model.totalReclaimable == 3_400 + 120 + 1_100 + 6_800)
    }

    @Test func volumesStartUnselected() async {
        let model = CleanupViewModel(maintenance: FakeMaintenance(usage: usage))
        await model.scan()
        #expect(model.selected == [.images, .containers, .buildCache])
        #expect(model.selectedBytes == 3_400 + 120 + 6_800)
    }

    @Test func togglingChangesTheSelectedTotal() async {
        let model = CleanupViewModel(maintenance: FakeMaintenance(usage: usage))
        await model.scan()
        model.toggle(.volumes)
        model.toggle(.buildCache)
        #expect(model.selected == [.images, .containers, .volumes])
        #expect(model.selectedBytes == 3_400 + 120 + 1_100)
    }

    @Test func cleanUpPrunesOnlySelectedCategoriesAndRescans() async {
        let maintenance = FakeMaintenance(usage: usage)
        let model = CleanupViewModel(maintenance: maintenance)
        await model.scan()

        await model.cleanUp()

        #expect(Set(maintenance.pruned) == [.images, .containers, .buildCache])
        #expect(model.lastFreedBytes == Int64(3_400 + 120 + 6_800))
        #expect(maintenance.scans == 2)
        #expect(model.isCleaning == false)
    }

    @Test func pruneFailureIsReported() async {
        let maintenance = FakeMaintenance(usage: usage)
        maintenance.pruneError = DockerError.requestFailed(status: 409, message: "a prune operation is already running")
        let model = CleanupViewModel(maintenance: maintenance)
        await model.scan()

        await model.cleanUp()
        #expect(model.errorMessage == "a prune operation is already running")
        #expect(model.lastFreedBytes == nil)
    }
}
