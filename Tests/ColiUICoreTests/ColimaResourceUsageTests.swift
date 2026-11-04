import Testing
@testable import ColiUICore

@Suite struct ColimaResourceUsageTests {
    @Test func readsTheLastLineTheScriptPrints() {
        let output = "Warning: something from ssh\n12.50 2254857216 4095127552 22561460224 105087164416\n"
        #expect(ColimaResourceUsage.parse(output) == ColimaResourceUsage(
            cpuPercent: 12.5, memoryUsedBytes: 2_254_857_216, memoryTotalBytes: 4_095_127_552,
            diskUsedBytes: 22_561_460_224, diskTotalBytes: 105_087_164_416
        ))
    }

    @Test func clampsCPUAndRejectsBrokenOutput() {
        #expect(ColimaResourceUsage.parse("130.0 1 2 3 4")?.cpuPercent == 100)
        #expect(ColimaResourceUsage.parse("-1 1 2 3 4")?.cpuPercent == 0)
        #expect(ColimaResourceUsage.parse("") == nil)
        #expect(ColimaResourceUsage.parse("12 1 2 3") == nil)
        #expect(ColimaResourceUsage.parse("12 1 0 3 4") == nil)
        #expect(ColimaResourceUsage.parse("12 1 2 3 0") == nil)
    }

    /// Docker's images, volumes and containers live on Colima's data disk, not the VM's small root disk.
    @Test func theScriptMeasuresDockersDataDisk() {
        #expect(ColimaCLIRuntime.resourceScript.contains("df -Pk /var/lib/docker"))
    }
}
