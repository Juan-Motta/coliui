import Foundation
import Testing
@testable import ColiUICore

final class FakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _invocations: [[String]] = []
    var result: CommandResult

    init(result: CommandResult) { self.result = result }

    var invocations: [[String]] { lock.withLock { _invocations } }

    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        lock.withLock { _invocations.append([executable] + arguments) }
        return result
    }
}

@Suite struct ColimaCLIRuntimeTests {
    static let listOutput = """
    {"name":"default","status":"Running","arch":"aarch64","cpus":4,"memory":4294967296,"disk":107374182400,"runtime":"docker"}
    {"name":"work","status":"Stopped","arch":"x86_64","cpus":2,"memory":2147483648,"disk":64424509440,"runtime":"containerd"}

    """

    @Test func parsesOneInstancePerLine() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: Self.listOutput, stderr: ""))
        let instances = try await ColimaCLIRuntime(runner: runner, executable: "/bin/colima").instances()

        #expect(runner.invocations == [["/bin/colima", "list", "--json"]])
        #expect(instances.map(\.name) == ["default", "work"])
        #expect(instances[0].status == .running)
        #expect(instances[0].resourcesSummary == "4 CPU · 4 GiB · 100 GiB")
        #expect(instances[1].status == .stopped)
        #expect(instances[1].runtime == "containerd")
    }

    @Test func emptyOutputMeansNoInstances() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "\n", stderr: ""))
        #expect(try await ColimaCLIRuntime(runner: runner, executable: "colima").instances().isEmpty)
    }

    @Test(arguments: ["start", "stop", "restart"])
    func lifecycleCommandsTargetTheProfile(command: String) async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        let runtime = ColimaCLIRuntime(runner: runner, executable: "colima")
        switch command {
        case "start": try await runtime.start(profile: "work")
        case "stop": try await runtime.stop(profile: "work")
        default: try await runtime.restart(profile: "work")
        }
        #expect(runner.invocations == [["colima", command, "work"]])
    }

    @Test func failedCommandSurfacesLastStderrLine() async {
        let stderr = "time=x level=info msg=starting\ntime=y level=fatal msg=\"error starting vm\"\n"
        let runner = FakeRunner(result: CommandResult(exitCode: 1, stdout: "", stderr: stderr))
        await #expect(throws: ColimaError.commandFailed("time=y level=fatal msg=\"error starting vm\"")) {
            try await ColimaCLIRuntime(runner: runner, executable: "colima").start(profile: "default")
        }
    }

    @Test func malformedJSONIsReported() async {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "{not json}\n", stderr: ""))
        await #expect(throws: ColimaError.unexpectedOutput) {
            try await ColimaCLIRuntime(runner: runner, executable: "colima").instances()
        }
    }

    @Test func locatesHomebrewBinaryFirst() {
        let found = ColimaCLIRuntime.locateExecutable { $0 == "/usr/local/bin/colima" }
        #expect(found == "/usr/local/bin/colima")
        #expect(ColimaCLIRuntime.locateExecutable { _ in false } == nil)
    }
}
