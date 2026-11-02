import ColiUICore
import Foundation
import Observation

struct PortRow: Identifiable, Equatable {
    let id = UUID()
    var host = ""
    var container = ""
    var proto = "tcp"
}

struct VolumeRow: Identifiable, Equatable {
    let id = UUID()
    var source = ""
    var target = ""
}

struct EnvRow: Identifiable, Equatable {
    let id = UUID()
    var key = ""
    var value = ""
}

/// The "Run a new container" form. Empty rows are ignored; filled rows must be valid.
@MainActor
@Observable
final class RunContainerViewModel {
    var image = ""
    var name = ""
    var ports = [PortRow()]
    var volumes = [VolumeRow()]
    var environment = [EnvRow()]
    var restartPolicy: RestartPolicy = .unlessStopped
    var autoRemove = false
    var pull = true
    private(set) var isRunning = false
    /// Validation is shown once the user tries to run.
    private(set) var showValidation = false
    var errorMessage: String?

    private let runner: ContainerRunner

    init(runner: ContainerRunner) {
        self.runner = runner
    }

    // MARK: Validation

    var validationError: String? {
        let image = image.trimmingCharacters(in: .whitespaces)
        if image.isEmpty { return "Enter an image, like nginx:latest." }
        let name = name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, let error = DockerName.formatError(name) { return error }
        for row in filledPorts {
            if Self.port(row.container) == nil { return "Container port must be a number from 1 to 65535." }
            if !row.host.trimmingCharacters(in: .whitespaces).isEmpty, Self.port(row.host) == nil {
                return "Host port must be a number from 1 to 65535."
            }
        }
        if filledVolumes.contains(where: { $0.source.trimmingCharacters(in: .whitespaces).isEmpty || !$0.target.hasPrefix("/") }) {
            return "Each volume needs a source and an absolute container path."
        }
        if filledEnvironment.contains(where: { $0.key.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Each variable needs a name."
        }
        if autoRemove, restartPolicy != .no {
            return "“Remove when stopped” can't be combined with a restart policy."
        }
        return nil
    }

    var request: RunRequest? {
        validationError == nil ? draft : nil
    }

    /// Live preview: built from whatever is valid so far.
    var commandPreview: String { draft.dockerRunCommand(maskSecrets: true) }
    var commandToCopy: String { draft.dockerRunCommand(maskSecrets: false) }

    private var draft: RunRequest {
        let name = name.trimmingCharacters(in: .whitespaces)
        return RunRequest(
            image: image.trimmingCharacters(in: .whitespaces).isEmpty ? "IMAGE" : image.trimmingCharacters(in: .whitespaces),
            name: name.isEmpty ? nil : name,
            ports: filledPorts.compactMap { row in
                Self.port(row.container).map { PortBinding(hostPort: Self.port(row.host), containerPort: $0, proto: row.proto) }
            },
            volumes: filledVolumes.map {
                VolumeBinding(source: $0.source.trimmingCharacters(in: .whitespaces), target: $0.target.trimmingCharacters(in: .whitespaces))
            },
            environment: filledEnvironment.map {
                EnvironmentVariable(key: $0.key.trimmingCharacters(in: .whitespaces), value: $0.value)
            },
            restartPolicy: restartPolicy,
            autoRemove: autoRemove,
            pull: pull
        )
    }

    private var filledPorts: [PortRow] {
        ports.filter { !($0.host + $0.container).trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var filledVolumes: [VolumeRow] {
        volumes.filter { !($0.source + $0.target).trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var filledEnvironment: [EnvRow] {
        environment.filter { !($0.key + $0.value).trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func port(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), (1...65535).contains(value) else { return nil }
        return value
    }

    // MARK: Actions

    /// Returns the started container's name (or short ID) on success.
    func run() async -> String? {
        showValidation = true
        guard let request else { return nil }
        isRunning = true
        defer { isRunning = false }
        do {
            let id = try await runner.run(request)
            errorMessage = nil
            return request.name ?? String(id.prefix(12))
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importEnv(_ text: String) {
        let imported = Self.parseEnv(text).map { EnvRow(key: $0.key, value: $0.value) }
        environment = environment.filter { !($0.key + $0.value).isEmpty } + imported
        if environment.isEmpty { environment = [EnvRow()] }
    }

    /// `KEY=value` lines; skips blanks, comments and malformed lines; accepts `export` and quotes.
    static func parseEnv(_ text: String) -> [EnvironmentVariable] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard let equals = line.firstIndex(of: "=") else { return nil }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            return EnvironmentVariable(key: key, value: value)
        }
    }
}
