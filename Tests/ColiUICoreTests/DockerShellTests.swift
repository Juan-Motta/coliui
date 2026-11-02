import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

@Suite struct DockerShellTests {
    @Test func createsATTYExecWithStdin() async throws {
        let transport = FakeTransport(response: response(201, #"{"Id":"ex123"}"#))
        let id = try await DockerEngineRepository(transport: transport)
            .createExec(containerID: "e81b3f0c55d2", shell: "/bin/bash", user: "root", columns: 120, rows: 40)

        #expect(id == "ex123")
        #expect(transport.calls == [.init(method: "POST", path: "/containers/e81b3f0c55d2/exec")])
        let body = try #require(transport.bodies.first ?? nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["Cmd"] as? [String] == ["/bin/bash"])
        #expect(json["User"] as? String == "root")
        #expect(json["Tty"] as? Bool == true)
        #expect(json["AttachStdin"] as? Bool == true)
        #expect(json["AttachStdout"] as? Bool == true)
        #expect(json["AttachStderr"] as? Bool == true)
        #expect(json["Env"] as? [String] == ["TERM=xterm-256color"])
        #expect(json["ConsoleSize"] as? [Int] == [40, 120])
    }

    @Test func emptyUserUsesTheImageDefault() async throws {
        let transport = FakeTransport(response: response(201, #"{"Id":"ex"}"#))
        _ = try await DockerEngineRepository(transport: transport)
            .createExec(containerID: "abc", shell: "/bin/sh", user: "  ", columns: 80, rows: 24)
        let json = try #require(try JSONSerialization.jsonObject(with: transport.bodies.first!!) as? [String: Any])
        #expect(json["User"] == nil)
    }

    @Test func refusesUnsafeContainerIDs() async {
        let transport = FakeTransport(response: response(201))
        await #expect(throws: DockerError.invalidContainerID) {
            _ = try await DockerEngineRepository(transport: transport)
                .createExec(containerID: "../x", shell: "/bin/sh", user: "", columns: 80, rows: 24)
        }
    }

    @Test func resizes() async throws {
        let transport = FakeTransport(response: response(201))
        try await DockerEngineRepository(transport: transport).resizeExec(id: "ex123", columns: 132, rows: 43)
        #expect(transport.calls == [.init(method: "POST", path: "/exec/ex123/resize?h=43&w=132")])
    }

    @Test func startRequestAsksForAnUpgrade() {
        let request = String(decoding: DockerShell.startRequest(execID: "ex123"), as: UTF8.self)
        #expect(request.hasPrefix("POST /exec/ex123/start HTTP/1.1\r\n"))
        #expect(request.contains("Connection: Upgrade\r\n"))
        #expect(request.contains("Upgrade: tcp\r\n"))
        #expect(request.hasSuffix("\r\n\r\n" + #"{"Detach":false,"Tty":true}"#))
    }

    @Test func upgradeHandsOverTheBytesAfterTheHead() throws {
        var raw = Data("HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n".utf8)
        raw.append(Data("root@abc:/# ".utf8))
        let rest = try #require(try DockerShell.upgrade(raw))
        #expect(String(decoding: rest, as: UTF8.self) == "root@abc:/# ")
        #expect(try DockerShell.upgrade(Data("HTTP/1.1 101 UPG".utf8)) == nil)
    }

    @Test func upgradeFailuresCarryTheEngineMessage() {
        let raw = Data("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n\r\n{\"message\":\"No such exec instance: ex123\"}".utf8)
        #expect(throws: DockerError.requestFailed(status: 404, message: "No such exec instance: ex123")) {
            _ = try DockerShell.upgrade(raw)
        }
    }
}
