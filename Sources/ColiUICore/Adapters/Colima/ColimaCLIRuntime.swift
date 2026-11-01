import Foundation

public enum ColimaError: Error, Equatable, LocalizedError {
    case notInstalled
    case commandFailed(String)
    case unexpectedOutput

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Colima isn't installed. Install it with `brew install colima`."
        case .commandFailed(let message): message
        case .unexpectedOutput: "Colima returned output ColiUI couldn't read."
        }
    }
}

/// `ColimaRuntime` that drives the `colima` CLI (Colima has no API).
public struct ColimaCLIRuntime: ColimaRuntime {
    private let runner: CommandRunner
    private let executable: String

    public init(runner: CommandRunner, executable: String) {
        self.runner = runner
        self.executable = executable
    }

    public static let candidatePaths = ["/opt/homebrew/bin/colima", "/usr/local/bin/colima"]

    public static func locateExecutable(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidatePaths.first(where: fileExists)
    }

    public func instances() async throws -> [ColimaInstance] {
        let output = try await execute(["list", "--json"])
        // One JSON object per line.
        return try output
            .split(whereSeparator: \.isNewline)
            .map { line in
                guard let dto = try? JSONDecoder().decode(InstanceDTO.self, from: Data(line.utf8)) else {
                    throw ColimaError.unexpectedOutput
                }
                return dto.toDomain()
            }
    }

    public func start(profile: String) async throws {
        _ = try await execute(["start", profile])
    }

    public func stop(profile: String) async throws {
        _ = try await execute(["stop", profile])
    }

    public func restart(profile: String) async throws {
        _ = try await execute(["restart", profile])
    }

    private func execute(_ arguments: [String]) async throws -> String {
        let result = try await runner.run(executable, arguments)
        guard result.exitCode == 0 else {
            let lastLine = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init)
            throw ColimaError.commandFailed(lastLine ?? "colima \(arguments.joined(separator: " ")) failed.")
        }
        return result.stdout
    }
}

private struct InstanceDTO: Decodable {
    let name: String
    let status: String
    let arch: String
    let cpus: Int
    let memory: Int64
    let disk: Int64
    let runtime: String

    func toDomain() -> ColimaInstance {
        ColimaInstance(
            name: name,
            status: ColimaStatus(rawValue: status),
            arch: arch,
            cpus: cpus,
            memoryBytes: memory,
            diskBytes: disk,
            runtime: runtime
        )
    }
}
