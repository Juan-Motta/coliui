import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func container(_ state: ContainerState, _ status: String, id: String = "c1", name: String = "worker-jobs") -> Container {
    Container(id: id, name: name, image: "worker", state: state, status: status)
}

@Suite struct AlertRulesTests {
    /// Short-lived containers come and go; what the rules remember must not grow forever.
    @Test func forgetsContainersThatAreGone() {
        var rules = AlertRules()
        for index in 0..<50 {
            _ = rules.containersChanged([container(.restarting, "Restarting", id: "c\(index)")], now: t0)
        }
        _ = rules.containersChanged([container(.running, "Up", id: "keep")], now: t0)
        #expect(rules.trackedContainers == 1)
    }

    @Test func crashAlertsOnlyForNonZeroExitAfterRunning() {
        var rules = AlertRules()
        #expect(rules.containersChanged([container(.exited, "Exited (1) 2 hours ago")], now: t0).isEmpty)
        #expect(rules.containersChanged([container(.running, "Up 1 second")], now: t0).isEmpty)

        let alerts = rules.containersChanged([container(.exited, "Exited (137) 1 second ago")], now: t0)
        #expect(alerts == [Alert(kind: .containerCrashed, title: "worker-jobs exited with code 137",
                                 body: "It stopped unexpectedly. Open ColiUI to read its logs.", identifier: "crash-c1")])

        _ = rules.containersChanged([container(.running, "Up 1 second")], now: t0)
        #expect(rules.containersChanged([container(.exited, "Exited (0) 1 second ago")], now: t0).isEmpty)
    }

    @Test func restartLoopNeedsMoreThanThreeRestartsWithinFiveMinutes() {
        var rules = AlertRules()
        var alerts: [Alert] = []
        _ = rules.containersChanged([container(.running, "Up")], now: t0)
        for minute in 0..<4 {
            let at = t0.addingTimeInterval(Double(minute) * 60)
            alerts += rules.containersChanged([container(.restarting, "Restarting (1) 1 second ago")], now: at)
            alerts += rules.containersChanged([container(.running, "Up 1 second")], now: at.addingTimeInterval(5))
        }
        let loops = alerts.filter { $0.kind == .restartLoop }
        #expect(loops.count == 1)
        #expect(loops.first?.title == "worker-jobs is restarting in a loop")
        #expect(loops.first?.body == "4 restarts in the last 5 minutes.")
    }

    @Test func slowRestartsAreNotALoop() {
        var rules = AlertRules()
        var alerts: [Alert] = []
        _ = rules.containersChanged([container(.running, "Up")], now: t0)
        for minute in stride(from: 0, to: 40, by: 10) {
            let at = t0.addingTimeInterval(Double(minute) * 60)
            alerts += rules.containersChanged([container(.restarting, "Restarting (1)")], now: at)
            alerts += rules.containersChanged([container(.running, "Up")], now: at.addingTimeInterval(5))
        }
        #expect(alerts.filter { $0.kind == .restartLoop }.isEmpty)
    }

    @Test func colimaStoppingUnexpectedlyAlerts() {
        var rules = AlertRules()
        #expect(rules.colimaChanged(isRunning: true, userStopped: false, profile: "default").isEmpty)
        #expect(rules.colimaChanged(isRunning: false, userStopped: false, profile: "default")
                == [Alert(kind: .colimaStopped, title: "Colima “default” stopped",
                          body: "Docker isn't available until the VM starts again.", identifier: "colima-stopped")])
        _ = rules.colimaChanged(isRunning: true, userStopped: false, profile: "default")
        #expect(rules.colimaChanged(isRunning: false, userStopped: true, profile: "default").isEmpty)
    }

    @Test func colimaStartFailure() {
        #expect(AlertRules.colimaStartFailed(profile: "work", message: "exit status 1")
                == Alert(kind: .colimaStopped, title: "Colima “work” failed to start", body: "exit status 1", identifier: "colima-failed"))
    }

    @Test func diskAlertsOnceWhenPassingEightyPercent() {
        var rules = AlertRules()
        let gib: Int64 = 1 << 30
        #expect(rules.diskMeasured(used: 70 * gib, capacity: 100 * gib, profile: "default").isEmpty)
        let alerts = rules.diskMeasured(used: 82 * gib, capacity: 100 * gib, profile: "default")
        #expect(alerts == [Alert(kind: .diskAlmostFull, title: "Colima “default” disk is 82% full",
                                 body: "Open Cleanup to free space.", identifier: AlertRules.diskIdentifier)])
        #expect(rules.diskMeasured(used: 90 * gib, capacity: 100 * gib, profile: "default").isEmpty)
        _ = rules.diskMeasured(used: 50 * gib, capacity: 100 * gib, profile: "default")
        #expect(rules.diskMeasured(used: 85 * gib, capacity: 100 * gib, profile: "default").count == 1)
        #expect(rules.diskMeasured(used: 1, capacity: 0, profile: "default").isEmpty)
    }

    @Test func pullFinishedOnlyForLongPulls() {
        #expect(AlertRules.pullFinished(reference: "nginx", duration: .seconds(4)) == nil)
        #expect(AlertRules.pullFinished(reference: "node:22", duration: .seconds(42))
                == Alert(kind: .pullFinished, title: "Pulled node:22", body: "Took 42 s.", identifier: "pull-node:22"))
    }
}

@MainActor
@Suite struct AlertHookTests {
    @Test func colimaReportsUserStopsAndStartFailures() async {
        let runtime = FakeColimaRuntime(ColimaViewModelTests.instances)
        let model = ColimaViewModel(runtime: runtime, profile: "default")
        var refreshed = 0
        var failures: [String] = []
        model.onRefresh = { _ in refreshed += 1 }
        model.onStartFailed = { failures.append($0) }

        // What `colima list` reports once the stop finished.
        runtime.instancesResult = [ColimaInstance(name: "default", status: .stopped, arch: "aarch64", cpus: 4,
                                                  memoryBytes: 4 << 30, diskBytes: 100 << 30, runtime: "docker")]
        await model.perform(.stop)
        #expect(model.stoppedByUser)
        #expect(refreshed == 1)

        runtime.commandError = ColimaError.notInstalled
        await model.perform(.start)
        #expect(failures.count == 1)
    }

    @Test func imagesReportFinishedPulls() async {
        let puller = FakeImagePuller()
        let model = ImagesViewModel(repository: FakeImageRepository(images: []), puller: puller, containers: { [] }, toastDuration: .zero)
        var finished: [String] = []
        model.onPullFinished = { reference, _ in finished.append(reference) }
        model.openPull()
        model.pullReference = "nginx"
        await model.pull()
        #expect(finished == ["nginx"])
    }

    @Test func cleanupReportsScans() async {
        let usage = DiskUsage(
            images: DiskCategory(totalBytes: 10, reclaimableBytes: 0, reclaimableItems: []),
            containers: DiskCategory(totalBytes: 0, reclaimableBytes: 0, reclaimableItems: []),
            volumes: DiskCategory(totalBytes: 0, reclaimableBytes: 0, reclaimableItems: []),
            buildCache: DiskCategory(totalBytes: 0, reclaimableBytes: 0, reclaimableItems: [])
        )
        let model = CleanupViewModel(maintenance: FakeMaintenance(usage: usage))
        var scanned: [Int64] = []
        model.onScan = { scanned.append($0.totalBytes) }
        await model.scan()
        #expect(scanned == [10])
    }
}
