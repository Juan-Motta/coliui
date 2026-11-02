import Foundation

public enum ColimaError: Error, Equatable, LocalizedError {
    case notInstalled
    case commandFailed(String)
    case unexpectedOutput
    /// A read that didn't answer in time, usually a stuck VM.
    case timedOut(String)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let command): "`\(command)` didn't answer in time. The Colima VM may be stuck; try `colima stop` in a terminal."
        case .notInstalled: "Colima isn't installed. Install it with `brew install colima`."
        case .commandFailed(let message): message
        case .unexpectedOutput: "Colima returned output ColiUI couldn't read."
        }
    }
}

/// `ColimaRuntime` that drives the `colima` CLI (Colima has no API).
public struct ColimaCLIRuntime: ColimaRuntime, ColimaVersionSource {
    private let runner: CommandRunner
    private let executable: String
    private let readConfig: @Sendable (String) -> String?
    /// How long `list` and `status` may take; starting, creating or deleting a VM has no limit.
    private let readTimeout: Duration

    public init(
        runner: CommandRunner,
        executable: String,
        readConfig: @escaping @Sendable (String) -> String? = ColimaCLIRuntime.readConfigFile,
        readTimeout: Duration = .seconds(30)
    ) {
        self.runner = runner
        self.executable = executable
        self.readConfig = readConfig
        self.readTimeout = readTimeout
    }

    public static let readConfigFile: @Sendable (String) -> String? = { profile in
        try? String(contentsOfFile: "\(NSHomeDirectory())/.colima/\(profile)/colima.yaml", encoding: .utf8)
    }

    public func settings(profile: String) async throws -> ColimaProfileSettings {
        guard let yaml = readConfig(profile), let settings = ColimaProfileSettings(yaml: yaml) else {
            throw ColimaError.unexpectedOutput
        }
        return settings
    }

    public func apply(_ settings: ColimaProfileSettings, to profile: String, isRunning: Bool) async throws {
        if isRunning { _ = try await execute(["stop", profile]) }
        _ = try await execute(["start", profile] + settings.resourceArguments)
    }

    public func create(profile: String, settings: ColimaProfileSettings) async throws {
        _ = try await execute(["start", profile] + settings.resourceArguments
            + ["--vm-type", settings.vmType, "--runtime", settings.runtime])
    }

    public func delete(profile: String) async throws {
        _ = try await execute(["delete", profile, "--force"])
    }

    public static let candidatePaths = ["/opt/homebrew/bin/colima", "/usr/local/bin/colima"]

    public static func locateExecutable(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidatePaths.first(where: fileExists)
    }

    public func instances() async throws -> [ColimaInstance] {
        let output = try await execute(["list", "--json"], timeout: readTimeout)
        // One JSON object per line.
        let dtos = try output
            .split(whereSeparator: \.isNewline)
            .map { line in
                guard let dto = try? JSONDecoder().decode(InstanceDTO.self, from: Data(line.utf8)) else {
                    throw ColimaError.unexpectedOutput
                }
                return dto
            }
        // `list` doesn't report the VM driver; `status` does, but only for a running profile.
        // Each `status` launches colima, so the running profiles are asked at the same time.
        let vmTypes = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, dto) in dtos.enumerated() where ColimaStatus(rawValue: dto.status) == .running {
                group.addTask { (index, await vmType(profile: dto.name)) }
            }
            var found: [Int: String] = [:]
            for await (index, vmType) in group { found[index] = vmType }
            return found
        }
        return dtos.enumerated().map { index, dto in dto.toDomain(vmType: vmTypes[index]) }
    }

    public static func vmType(forDriver driver: String) -> String {
        let lowered = driver.lowercased()
        if lowered.contains("virtualization") { return "vz" }
        if lowered.contains("qemu") { return "qemu" }
        return lowered
    }

    private func vmType(profile: String) async -> String? {
        guard let output = try? await execute(["status", profile, "--json"], timeout: readTimeout),
              let dto = try? JSONDecoder().decode(StatusDTO.self, from: Data(output.utf8)) else { return nil }
        return Self.vmType(forDriver: dto.driver)
    }

    /// `colima version` prints "colima version 0.10.3" first.
    public func version() async throws -> String {
        let output = try await execute(["version"], timeout: readTimeout)
        guard let line = output.split(whereSeparator: \.isNewline).first, line.hasPrefix("colima version ") else {
            throw ColimaError.unexpectedOutput
        }
        return String(line.dropFirst("colima version ".count))
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

    private func execute(_ arguments: [String], timeout: Duration? = nil) async throws -> String {
        let result = try await run(arguments, timeout: timeout)
        guard result.exitCode == 0 else {
            let lastLine = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init)
            throw ColimaError.commandFailed(lastLine ?? "colima \(arguments.joined(separator: " ")) failed.")
        }
        return result.stdout
    }

    /// With a timeout, races the command against a sleep; the loser is cancelled, which terminates the process.
    private func run(_ arguments: [String], timeout: Duration?) async throws -> CommandResult {
        guard let timeout else { return try await runner.run(executable, arguments) }
        let (runner, executable) = (runner, executable)
        return try await withThrowingTaskGroup(of: CommandResult?.self) { group in
            group.addTask { try await runner.run(executable, arguments) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() ?? nil else {
                throw ColimaError.timedOut("colima " + (arguments.first ?? ""))
            }
            return result
        }
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

    func toDomain(vmType: String?) -> ColimaInstance {
        ColimaInstance(
            name: name,
            status: ColimaStatus(rawValue: status),
            arch: arch,
            cpus: cpus,
            memoryBytes: memory,
            diskBytes: disk,
            runtime: runtime,
            vmType: vmType
        )
    }
}

private struct StatusDTO: Decodable {
    let driver: String
}
