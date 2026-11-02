import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult
}

/// Runs a process with a PATH that includes Homebrew, since GUI apps don't inherit the shell PATH
/// and `colima` shells out to `limactl` and `docker`.
public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        try await BlockingIO.run {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            let basePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = [basePath, environment["PATH"]].compactMap { $0 }.joined(separator: ":")
            process.environment = environment

            let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            defer {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }
            // Files instead of pipes: a chatty process can't block on a full pipe buffer.
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            try process.run()
            process.waitUntilExit()
            try stdoutHandle.close()
            try stderrHandle.close()

            return CommandResult(
                exitCode: process.terminationStatus,
                stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
                stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
            )
        }
    }
}
