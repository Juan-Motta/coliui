import Foundation

public struct PortBinding: Sendable, Hashable {
    /// `nil` lets Docker pick a free host port.
    public var hostPort: Int?
    public var containerPort: Int
    public var proto: String

    public init(hostPort: Int?, containerPort: Int, proto: String) {
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.proto = proto
    }
}

public struct VolumeBinding: Sendable, Hashable {
    /// A named volume, or an absolute host path for a bind mount.
    public var source: String
    public var target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public struct EnvironmentVariable: Sendable, Hashable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    /// The rule Inspect and Environment use (`SecretMask`).
    public var isSecret: Bool { SecretMask.isSecret(name: key, value: value) }
}

public enum RestartPolicy: String, CaseIterable, Sendable {
    case no
    case unlessStopped = "unless-stopped"
    case always
    case onFailure = "on-failure"
}

/// Everything `docker run -d` needs.
public struct RunRequest: Sendable, Equatable {
    public var image: String
    public var name: String?
    public var ports: [PortBinding]
    public var volumes: [VolumeBinding]
    public var environment: [EnvironmentVariable]
    public var restartPolicy: RestartPolicy
    public var autoRemove: Bool
    public var pull: Bool

    public init(
        image: String, name: String?, ports: [PortBinding], volumes: [VolumeBinding],
        environment: [EnvironmentVariable], restartPolicy: RestartPolicy, autoRemove: Bool, pull: Bool
    ) {
        self.image = image
        self.name = name
        self.ports = ports
        self.volumes = volumes
        self.environment = environment
        self.restartPolicy = restartPolicy
        self.autoRemove = autoRemove
        self.pull = pull
    }

    /// The matching CLI command, one flag per line like the design.
    public func dockerRunCommand(maskSecrets: Bool) -> String {
        var head = "docker run -d"
        if autoRemove { head += " --rm" }
        if let name { head += " --name \(Self.quoted(name))" }
        var lines = [head]
        lines += ports.map { port in
            let container = port.proto == "tcp" ? "\(port.containerPort)" : "\(port.containerPort)/\(port.proto)"
            return "-p " + (port.hostPort.map { "\($0):\(container)" } ?? container)
        }
        lines += volumes.map { "-v \(Self.quoted("\($0.source):\($0.target)"))" }
        lines += environment.map { variable in
            let value = maskSecrets && variable.isSecret ? "••••••" : variable.value
            return "-e \(Self.quoted("\(variable.key)=\(value)"))"
        }
        if restartPolicy != .no { lines.append("--restart \(restartPolicy.rawValue)") }
        lines.append(Self.quoted(image))
        return lines.enumerated().map { $0.offset == 0 ? $0.element : "  " + $0.element }.joined(separator: " \\\n")
    }

    /// "localhost:5000/team/api:2.1" → ("localhost:5000/team/api", "2.1"); no tag means "latest".
    /// A digest ("nginx@sha256:…") takes the tag's place, as the Engine API expects.
    public static func imageParts(_ reference: String) -> (repository: String, tag: String) {
        if let at = reference.firstIndex(of: "@") {
            let name = String(reference[..<at])
            return (imageParts(name).repository, String(reference[reference.index(after: at)...]))
        }
        let lastSlash = reference.lastIndex(of: "/") ?? reference.startIndex
        if let colon = reference[lastSlash...].lastIndex(of: ":") {
            return (String(reference[..<colon]), String(reference[reference.index(after: colon)...]))
        }
        return (reference, "latest")
    }

    private static func quoted(_ text: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@•,+%"))
        guard text.unicodeScalars.contains(where: { !safe.contains($0) }) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
