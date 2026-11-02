import Foundation
import Testing
@testable import ColiUICore

@Suite struct ColimaProfilesTests {
    static let yaml = """
    # Number of CPUs to be allocated to the virtual machine.
    cpu: 4

    disk: 100
    memory: 4
    arch: aarch64
    runtime: docker
    kubernetes:
      enabled: false
      version: v1.33.4+k3s1
    vmType: vz
    rosetta: true
    mountType: virtiofs
    """

    @Test func readsSettingsFromTheProfileConfig() throws {
        let settings = try #require(ColimaProfileSettings(yaml: Self.yaml))
        #expect(settings == ColimaProfileSettings(
            cpus: 4, memoryGiB: 4, diskGiB: 100, vmType: "vz", mountType: "virtiofs", rosetta: true, runtime: "docker"
        ))
    }

    @Test func missingKeysFallBackToColimaDefaults() throws {
        let settings = try #require(ColimaProfileSettings(yaml: "cpu: 6\nmemory: 12.5\n"))
        #expect(settings.cpus == 6)
        #expect(settings.memoryGiB == 12.5)
        #expect(settings.diskGiB == 100)
        #expect(settings.vmType == "vz")
        #expect(settings.mountType == "virtiofs")
        #expect(settings.rosetta == false)
    }

    @Test func settingsRunsThroughTheConfigReader() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        let runtime = ColimaCLIRuntime(runner: runner, executable: "colima", readConfig: { profile in
            profile == "work" ? Self.yaml : nil
        })
        #expect(try await runtime.settings(profile: "work").cpus == 4)
        await #expect(throws: ColimaError.unexpectedOutput) { try await runtime.settings(profile: "nope") }
    }

    @Test func applyStopsARunningProfileThenStartsWithNewResources() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        let runtime = ColimaCLIRuntime(runner: runner, executable: "colima")
        let settings = ColimaProfileSettings(cpus: 6, memoryGiB: 8, diskGiB: 120, vmType: "vz", mountType: "sshfs", rosetta: false, runtime: "docker")
        try await runtime.apply(settings, to: "default", isRunning: true)
        #expect(runner.invocations == [
            ["colima", "stop", "default"],
            ["colima", "start", "default", "--cpus", "6", "--memory", "8", "--disk", "120", "--mount-type", "sshfs", "--vz-rosetta=false"],
        ])
    }

    @Test func applyToAStoppedProfileOnlyStarts() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        let settings = ColimaProfileSettings(cpus: 2, memoryGiB: 2.5, diskGiB: 100, vmType: "vz", mountType: "virtiofs", rosetta: true, runtime: "docker")
        try await ColimaCLIRuntime(runner: runner, executable: "colima").apply(settings, to: "work", isRunning: false)
        #expect(runner.invocations == [
            ["colima", "start", "work", "--cpus", "2", "--memory", "2.5", "--disk", "100", "--mount-type", "virtiofs", "--vz-rosetta=true"],
        ])
    }

    @Test func createPassesVMTypeAndRuntime() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        let settings = ColimaProfileSettings(cpus: 2, memoryGiB: 2, diskGiB: 60, vmType: "qemu", mountType: "9p", rosetta: true, runtime: "containerd")
        try await ColimaCLIRuntime(runner: runner, executable: "colima").create(profile: "x86-legacy", settings: settings)
        #expect(runner.invocations == [[
            "colima", "start", "x86-legacy", "--cpus", "2", "--memory", "2", "--disk", "60",
            "--mount-type", "9p", "--vm-type", "qemu", "--runtime", "containerd",
        ]])
    }

    @Test func deleteForcesWithoutPrompting() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        try await ColimaCLIRuntime(runner: runner, executable: "colima").delete(profile: "work")
        #expect(runner.invocations == [["colima", "delete", "work", "--force"]])
    }
}
