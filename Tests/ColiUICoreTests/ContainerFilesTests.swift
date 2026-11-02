import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: Data, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: headers, body: body)
}

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    response(status, Data(body.utf8))
}

/// Docker's multiplexed stream: an 8-byte header (stream, 0, 0, 0, big-endian size) per frame.
private func frame(_ text: String, stream: UInt8 = 1) -> Data {
    let payload = Data(text.utf8)
    let size = UInt32(payload.count)
    return Data([stream, 0, 0, 0, UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)]) + payload
}

/// A one-entry ustar archive.
private func tar(_ name: String, _ contents: Data, type: UInt8 = UInt8(ascii: "0")) -> Data {
    var header = [UInt8](repeating: 0, count: 512)
    for (index, byte) in name.utf8.prefix(100).enumerated() { header[index] = byte }
    let size = String(contents.count, radix: 8)
    let field = String(repeating: "0", count: 11 - size.count) + size
    for (index, byte) in field.utf8.enumerated() { header[124 + index] = byte }
    header[156] = type
    var data = Data(header) + contents
    data.append(Data(count: (512 - contents.count % 512) % 512))
    return data + Data(count: 1024)
}

/// Answers by method + path prefix, recording each call.
private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(method: String, path: String, body: String)] = []
    let routes: [(prefix: String, response: HTTPResponse)]

    init(_ routes: [(String, HTTPResponse)]) { self.routes = routes.map { ($0.0, $0.1) } }
    var calls: [(method: String, path: String, body: String)] { lock.withLock { _calls } }

    func send(method: String, path: String, body: Data?) async throws -> HTTPResponse {
        lock.withLock { _calls.append((method, path, body.map { String(decoding: $0, as: UTF8.self) } ?? "")) }
        let key = "\(method) \(path)"
        return routes.first { key.hasPrefix($0.prefix) }?.response ?? response(404, #"{"message":"not found"}"#)
    }
}

@Suite struct ContainerFileParsingTests {
    @Test func parsesStatLinesFoldersFirst() {
        let output = [
            "-rw-r--r--\t612\t1793500000\tnode:node\tregular file\tpackage.json\t'package.json'",
            "drwxr-xr-x\t4096\t1793400000\troot:root\tdirectory\tsrc\t'src'",
            "lrwxrwxrwx\t8\t1793300000\troot:root\tsymbolic link\tlib64\t'lib64' -> '/usr/lib'",
            "-rw-------\t214\t1793500000\tnode:node\tregular file\t.env\t'.env'",
            "-rw-r--r--\t0\t1793500000\troot:root\tregular empty file\tEMPTY\t'EMPTY'",
            "garbage line",
        ].joined(separator: "\n")

        let files = ContainerFile.parse(statOutput: output)

        #expect(files.map(\.name) == ["src", ".env", "EMPTY", "lib64", "package.json"])
        #expect(files[0].kind == .directory)
        #expect(files[1].mode == "-rw-------")
        #expect(files[1].owner == "node:node")
        #expect(files[2].kind == .file)
        #expect(files[3].kind == .symlink)
        #expect(files[3].linkTarget == "/usr/lib")
        #expect(files[4].size == 612)
        #expect(files[4].modified == Date(timeIntervalSince1970: 1_793_500_000))
    }

    /// `find` prints `./name`; the listing shows the bare name.
    @Test func stripsFindsDotSlash() {
        let output = "drwxr-xr-x\t4096\t1793400000\troot:root\tdirectory\t./src\t'./src'\n"
            + "lrwxrwxrwx\t8\t1793300000\troot:root\tsymbolic link\t./lib64\t'./lib64' -> '/usr/lib'"
        let files = ContainerFile.parse(statOutput: output)
        #expect(files.map(\.name) == ["src", "lib64"])
        #expect(files[1].linkTarget == "/usr/lib")
    }

    @Test func joinsAndClimbsPaths() {
        #expect(ContainerPath.child(of: "/", "app") == "/app")
        #expect(ContainerPath.child(of: "/app", "src") == "/app/src")
        #expect(ContainerPath.parent(of: "/app/src") == "/app")
        #expect(ContainerPath.parent(of: "/app") == "/")
        #expect(ContainerPath.parent(of: "/") == "/")
        #expect(ContainerPath.components(of: "/app/src") == ["app", "src"])
    }

    @Test func readsTheFirstFileOfATar() throws {
        let archive = tar("package.json", Data("{\"name\":\"api\"}".utf8))
        #expect(try TarArchive.firstFile(in: archive) == Data("{\"name\":\"api\"}".utf8))
    }

    @Test func skipsTarEntriesThatAreNotFiles() throws {
        let archive = tar("src/", Data(), type: UInt8(ascii: "5")).dropLast(1024) + tar("src/a.txt", Data("a".utf8))
        #expect(try TarArchive.firstFile(in: Data(archive)) == Data("a".utf8))
    }

    @Test func rejectsATruncatedTar() {
        #expect(throws: DockerError.malformedResponse) { try TarArchive.firstFile(in: Data(count: 100)) }
    }
}

@Suite struct DockerFilesTests {
    @Test func listsAFolderWithExec() async throws {
        let transport = ScriptedTransport([
            ("POST /containers/c1/exec", response(201, #"{"Id":"e1"}"#)),
            ("POST /exec/e1/start", response(200, frame("drwxr-xr-x\t4096\t1793400000\troot:root\tdirectory\tsrc\t'src'\n"))),
            ("GET /exec/e1/json", response(200, #"{"ExitCode":0}"#)),
        ])
        let files = try await DockerEngineRepository(transport: transport).listFiles(id: "c1", path: "/app")

        #expect(files.map(\.name) == ["src"])
        let create = try JSONSerialization.jsonObject(with: Data(transport.calls[0].body.utf8)) as? [String: Any]
        let command = create?["Cmd"] as? [String]
        #expect(command?.first == "sh")
        #expect(command?.last == "/app")
        #expect(create?["Tty"] as? Bool == false)
        #expect(create?["AttachStdin"] as? Bool != true)
        #expect(transport.calls[1].body == #"{"Detach":false,"Tty":false}"#)
    }

    @Test func explainsAFolderThatCantBeOpened() async {
        let transport = ScriptedTransport([
            ("POST /containers/c1/exec", response(201, #"{"Id":"e1"}"#)),
            ("POST /exec/e1/start", response(200, frame("sh: cd: can't cd to /root: Permission denied\n", stream: 2))),
            ("GET /exec/e1/json", response(200, #"{"ExitCode":3}"#)),
        ])
        await #expect(throws: ContainerFilesError.cannotOpen(path: "/root", reason: "sh: cd: can't cd to /root: Permission denied")) {
            try await DockerEngineRepository(transport: transport).listFiles(id: "c1", path: "/root")
        }
    }

    @Test func explainsContainersWithoutTools() async {
        let transport = ScriptedTransport([
            ("POST /containers/c1/exec", response(201, #"{"Id":"e1"}"#)),
            ("POST /exec/e1/start", response(200, Data())),
            ("GET /exec/e1/json", response(200, #"{"ExitCode":127}"#)),
        ])
        await #expect(throws: ContainerFilesError.noShell) {
            try await DockerEngineRepository(transport: transport).listFiles(id: "c1", path: "/")
        }
    }

    @Test func distrolessExecCreateFailureMeansNoShell() async {
        let transport = ScriptedTransport([
            ("POST /containers/c1/exec", response(201, #"{"Id":"e1"}"#)),
            ("POST /exec/e1/start", response(400, #"{"message":"OCI runtime exec failed: exec: \"sh\": executable file not found in $PATH"}"#)),
        ])
        await #expect(throws: ContainerFilesError.noShell) {
            try await DockerEngineRepository(transport: transport).listFiles(id: "c1", path: "/")
        }
    }

    @Test func readsAFileThroughTheArchiveAPI() async throws {
        let transport = ScriptedTransport([
            ("GET /containers/c1/archive?path=/app/my%20notes.txt", response(200, tar("my notes.txt", Data("hi".utf8)))),
        ])
        let data = try await DockerEngineRepository(transport: transport).readFile(id: "c1", path: "/app/my notes.txt")
        #expect(data == Data("hi".utf8))
    }

    @Test func archivesAFolder() async throws {
        let archive = tar("src/a.txt", Data("a".utf8))
        let transport = ScriptedTransport([("GET /containers/c1/archive?path=/app/src", response(200, archive))])
        #expect(try await DockerEngineRepository(transport: transport).archive(id: "c1", path: "/app/src") == archive)
    }

    @Test func refusesRelativePaths() async {
        let repository = DockerEngineRepository(transport: ScriptedTransport([]))
        await #expect(throws: ContainerFilesError.invalidPath) { try await repository.listFiles(id: "c1", path: "app") }
        await #expect(throws: ContainerFilesError.invalidPath) { try await repository.readFile(id: "c1", path: "") }
    }

    @Test func startsInTheWorkingDirectory() async throws {
        let transport = ScriptedTransport([("GET /containers/c1/json", response(200, #"{"Config":{"WorkingDir":"/app"}}"#))])
        #expect(try await DockerEngineRepository(transport: transport).workingDirectory(id: "c1") == "/app")

        let none = ScriptedTransport([("GET /containers/c1/json", response(200, #"{"Config":{"WorkingDir":""}}"#))])
        #expect(try await DockerEngineRepository(transport: none).workingDirectory(id: "c1") == "/")
    }
}
