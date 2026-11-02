import ColiUICore
import Foundation
import Observation

@MainActor
@Observable
final class CleanupViewModel {
    private(set) var usage: DiskUsage?
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var lastFreedBytes: Int64?
    /// Volumes start unselected: pruning them deletes data.
    private(set) var selected: Set<PruneTarget> = [.images, .containers, .buildCache]
    var showItems = false
    var confirmingCleanup = false
    var errorMessage: String?

    /// Called after every successful scan (Settings › Notifications › VM disk almost full).
    var onScan: ((DiskUsage) -> Void)?

    private let maintenance: DockerMaintenance
    private let now: () -> Date

    init(maintenance: DockerMaintenance, now: @escaping () -> Date = Date.init) {
        self.maintenance = maintenance
        self.now = now
    }

    var totalReclaimable: Int64 {
        PruneTarget.allCases.reduce(0) { $0 + (usage?.category($1).reclaimableBytes ?? 0) }
    }

    var selectedBytes: Int64 {
        selected.reduce(0) { $0 + (usage?.category($1).reclaimableBytes ?? 0) }
    }

    func toggle(_ target: PruneTarget) {
        if selected.contains(target) {
            selected.remove(target)
        } else {
            selected.insert(target)
        }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            usage = try await maintenance.diskUsage()
            lastScan = now()
            errorMessage = nil
            if let usage { onScan?(usage) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cleanUp() async {
        isCleaning = true
        defer { isCleaning = false }
        var freed: Int64 = 0
        // One at a time: the engine rejects concurrent prunes.
        for target in PruneTarget.allCases where selected.contains(target) {
            do {
                freed += try await maintenance.prune(target)
            } catch {
                let message = error.localizedDescription
                await scan()
                // A successful rescan clears errors; keep the prune failure visible.
                errorMessage = message
                return
            }
        }
        lastFreedBytes = freed
        await scan()
    }
}
