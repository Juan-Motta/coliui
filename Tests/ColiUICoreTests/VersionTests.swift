import Foundation
import Testing
@testable import ColiUICore

@Suite struct VersionTests {
    @Test func readsTheEngineVersion() async throws {
        let body = #"{"Platform":{"Name":"Docker Engine - Community"},"Version":"29.5.2","ApiVersion":"1.54","Os":"linux","Arch":"arm64"}"#
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8)))
        let version = try await DockerEngineRepository(transport: transport).engineVersion()
        #expect(transport.calls == [.init(method: "GET", path: "/version")])
        #expect(version == EngineVersion(version: "29.5.2", apiVersion: "1.54"))
    }

    @Test func readsTheColimaVersion() async throws {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "colima version 0.10.3\ngit commit: 00f6c297\n", stderr: ""))
        let version = try await ColimaCLIRuntime(runner: runner, executable: "/opt/homebrew/bin/colima").version()
        #expect(runner.invocations == [["/opt/homebrew/bin/colima", "version"]])
        #expect(version == "0.10.3")
    }

    @Test func unreadableColimaOutputIsAnError() async {
        let runner = FakeRunner(result: CommandResult(exitCode: 0, stdout: "something else", stderr: ""))
        await #expect(throws: ColimaError.unexpectedOutput) {
            try await ColimaCLIRuntime(runner: runner, executable: "colima").version()
        }
    }
}
