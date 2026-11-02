import Foundation

/// `ContainerFileBrowser` over the Engine API: folders are listed by running `stat` through a
/// non-interactive exec; files and folders are read through `/containers/{id}/archive` (a tar).
extension DockerEngineRepository: ContainerFileBrowser {
    /// `$1` is the folder. `find -exec … {} +` hands `stat` the entries in batches, so huge folders don't
    /// overflow the command line (a `*` glob did); entries that vanish or can't be read are skipped.
    static let listScript: String = {
        let format = ["%A", "%s", "%Y", "%U:%G", "%F", "%n", "%N"].joined(separator: "\t")
        return """
        command -v stat >/dev/null 2>&1 && command -v find >/dev/null 2>&1 || exit 127
        cd -- "$1" || exit 3
        find . -mindepth 1 -maxdepth 1 -exec stat -c '\(format)' -- {} + 2>/dev/null
        exit 0
        """
    }()

    public func listFiles(id: String, path: String) async throws -> [ContainerFile] {
        let id = try Self.validated(id)
        let path = try Self.validatedPath(path)
        let run = try await runCommand(containerID: id, command: ["sh", "-c", Self.listScript, "sh", path])
        switch run.exitCode {
        case 0: return ContainerFile.parse(statOutput: run.stdout)
        case 126, 127: throw ContainerFilesError.noShell
        default:
            let reason = run.stderr.split(separator: "\n").last.map(String.init) ?? ""
            throw ContainerFilesError.cannotOpen(path: path, reason: reason.trimmingCharacters(in: .whitespaces))
        }
    }

    public func readFile(id: String, path: String) async throws -> Data {
        try TarArchive.firstFile(in: try await archive(id: id, path: path))
    }

    public func archive(id: String, path: String) async throws -> Data {
        let id = try Self.validated(id)
        let path = try Self.validatedPath(path)
        let response = try await transport.send(method: "GET", path: "/containers/\(id)/archive?path=\(Self.queryEncoded(path))", body: nil)
        try Self.check(response)
        return response.body
    }

    public func workingDirectory(id: String) async throws -> String {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "GET", path: "/containers/\(id)/json", body: nil)
        try Self.check(response)
        let dto = try? JSONDecoder().decode(WorkingDirDTO.self, from: response.body)
        let directory = dto?.config?.workingDir ?? ""
        return directory.hasPrefix("/") ? directory : "/"
    }

    /// Runs a command without a TTY and collects its output and exit code.
    func runCommand(containerID: String, command: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int) {
        let payload: [String: Any] = ["AttachStdout": true, "AttachStderr": true, "Tty": false, "Cmd": command]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let exec = try await decode(ExecIDDTO.self, method: "POST", path: "/containers/\(containerID)/exec", body: body)
        let execID = try Self.validated(exec.id)

        let start = try await transport.send(method: "POST", path: "/exec/\(execID)/start", body: Data(#"{"Detach":false,"Tty":false}"#.utf8))
        do {
            try Self.check(start)
        } catch DockerError.requestFailed(_, let message) where message.contains("executable file not found") || message.contains("no such file or directory") {
            throw ContainerFilesError.noShell
        }
        let (stdout, stderr) = Self.demultiplex(start.body)

        let status = try await transport.send(method: "GET", path: "/exec/\(execID)/json", body: nil)
        try Self.check(status)
        let exitCode = (try? JSONDecoder().decode(ExecStatusDTO.self, from: status.body))?.exitCode ?? -1
        return (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self), exitCode)
    }

    /// Splits Docker's multiplexed stream (8-byte header per frame: stream, 0, 0, 0, big-endian size).
    static func demultiplex(_ data: Data) -> (stdout: Data, stderr: Data) {
        var stdout = Data(), stderr = Data()
        var index = data.startIndex
        while data.endIndex - index >= 8 {
            let size = Int(data[index + 4]) << 24 | Int(data[index + 5]) << 16 | Int(data[index + 6]) << 8 | Int(data[index + 7])
            let end = min(index + 8 + size, data.endIndex)
            if data[index] == 2 { stderr.append(data[(index + 8)..<end]) } else { stdout.append(data[(index + 8)..<end]) }
            index = end
        }
        return (stdout, stderr)
    }

    /// Absolute paths only, and nothing that could break the request line.
    static func validatedPath(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) else {
            throw ContainerFilesError.invalidPath
        }
        return path
    }

    static func queryEncoded(_ path: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

/// The parts of a ustar archive the Files tab needs.
enum TarArchive {
    /// The contents of the first regular file (type `0` or NUL), skipping folders and links.
    /// Reads the archive in place: copying it to an array first doubled the memory of a large preview or download.
    static func firstFile(in data: Data) throws -> Data {
        var offset = data.startIndex
        while data.endIndex - offset >= 512 {
            let header = data[offset..<offset + 512]
            if header.allSatisfy({ $0 == 0 }) { break }
            let sizeField = String(decoding: header.dropFirst(124).prefix(12), as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
            guard let size = Int(sizeField.isEmpty ? "0" : sizeField, radix: 8) else { throw DockerError.malformedResponse }
            let type = header[offset + 156]
            let start = offset + 512
            guard size <= data.endIndex - start else { throw DockerError.malformedResponse }
            if type == UInt8(ascii: "0") || type == 0 {
                return data.subdata(in: start..<start + size)
            }
            offset = start + (size + 511) / 512 * 512
        }
        throw DockerError.malformedResponse
    }
}

private struct ExecIDDTO: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

private struct ExecStatusDTO: Decodable {
    let exitCode: Int?
    enum CodingKeys: String, CodingKey { case exitCode = "ExitCode" }
}

private struct WorkingDirDTO: Decodable {
    struct ConfigDTO: Decodable {
        let workingDir: String?
        enum CodingKeys: String, CodingKey { case workingDir = "WorkingDir" }
    }
    let config: ConfigDTO?
    enum CodingKeys: String, CodingKey { case config = "Config" }
}
