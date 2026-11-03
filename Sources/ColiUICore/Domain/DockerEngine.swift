import Foundation

/// The local Docker engines ColiUI knows. Colima adds VM controls and profiles; the others are managed in their own app.
public enum DockerEngineKind: String, CaseIterable, Sendable {
    case colima, dockerDesktop, orbStack, rancherDesktop
    /// A custom socket or `DOCKER_HOST` that isn't one of the above.
    case other

    /// The order Automatic tries them in.
    public static let detectionOrder: [DockerEngineKind] = [.colima, .dockerDesktop, .orbStack, .rancherDesktop]

    public var displayName: String {
        switch self {
        case .colima: "Colima"
        case .dockerDesktop: "Docker Desktop"
        case .orbStack: "OrbStack"
        case .rancherDesktop: "Rancher Desktop"
        case .other: "Docker"
        }
    }

    /// The app that starts and stops this engine ("Open OrbStack"); nil for Colima (ColiUI controls it) and others.
    public var appBundleIdentifier: String? {
        switch self {
        case .dockerDesktop: "com.docker.docker"
        case .orbStack: "dev.kdrag0n.MacVirt"
        case .rancherDesktop: "io.rancherdesktop.app"
        case .colima, .other: nil
        }
    }

    public func socket(home: String, profile: String) -> String? {
        switch self {
        case .colima: "\(home)/.colima/\(profile)/docker.sock"
        case .dockerDesktop: "\(home)/.docker/run/docker.sock"
        case .orbStack: "\(home)/.orbstack/run/docker.sock"
        case .rancherDesktop: "\(home)/.rd/docker.sock"
        case .other: nil
        }
    }

    /// The engine a socket path belongs to: any profile under `~/.colima` is Colima, the others by their fixed path.
    public static func owning(socketPath path: String, home: String) -> DockerEngineKind {
        let colima = "\(home)/.colima/"
        if path.hasPrefix(colima), path.hasSuffix("/docker.sock"),
           !path.dropFirst(colima.count).dropLast("/docker.sock".count).contains("/") {
            return .colima
        }
        return detectionOrder.first { $0 != .colima && $0.socket(home: home, profile: "") == path } ?? .other
    }

    /// Names an engine reached through a custom socket or `DOCKER_HOST` from what it reports in `/info`.
    public static func identify(_ info: EngineInfo) -> DockerEngineKind {
        let system = info.operatingSystem.lowercased()
        if system.contains("docker desktop") { return .dockerDesktop }
        if system.contains("orbstack") { return .orbStack }
        if system.contains("rancher desktop") { return .rancherDesktop }
        if info.name == "colima" || info.name.hasPrefix("colima-") { return .colima }
        return .other
    }
}

/// What `/info` says about the engine: shown on the sidebar card and in the menu bar.
public struct EngineInfo: Sendable, Equatable {
    public let name: String
    public let operatingSystem: String
    public let serverVersion: String
    public let cpus: Int
    public let memoryBytes: Int64

    public init(name: String, operatingSystem: String, serverVersion: String, cpus: Int, memoryBytes: Int64) {
        self.name = name
        self.operatingSystem = operatingSystem
        self.serverVersion = serverVersion
        self.cpus = cpus
        self.memoryBytes = memoryBytes
    }

    /// "8 GiB", "3.8 GiB".
    public var memoryText: String {
        let gib = Double(memoryBytes) / 1_073_741_824
        return abs(gib - gib.rounded()) < 0.05 ? "\(Int(gib.rounded())) GiB" : ByteFormat.binary(memoryBytes)
    }

    /// "Engine 28.5.1 · 10 CPU · 8 GiB".
    public var summary: String {
        "Engine \(serverVersion) · \(cpus) CPU · \(memoryText)"
    }
}

/// The engine this session talks to and whether it answered when ColiUI started.
public struct DetectedEngine: Sendable, Equatable {
    public let kind: DockerEngineKind
    public let socketPath: String
    public let isAnswering: Bool

    public init(kind: DockerEngineKind, socketPath: String, isAnswering: Bool) {
        self.kind = kind
        self.socketPath = socketPath
        self.isAnswering = isAnswering
    }
}

public enum EngineDetection {
    /// Settings › Engine › Automatic: a `unix://` DOCKER_HOST wins; otherwise the first engine whose socket
    /// answers, in `detectionOrder`. With none answering it waits on Colima's socket, so starting Colima is picked up.
    public static func automatic(environment: [String: String], home: String, profile: String,
                                 answers: (String) -> Bool) -> DetectedEngine {
        if let host = environment["DOCKER_HOST"], host.hasPrefix("unix://") {
            let path = String(host.dropFirst("unix://".count))
            return DetectedEngine(kind: .owning(socketPath: path, home: home), socketPath: path, isAnswering: answers(path))
        }
        for kind in DockerEngineKind.detectionOrder {
            guard let path = kind.socket(home: home, profile: profile), answers(path) else { continue }
            return DetectedEngine(kind: kind, socketPath: path, isAnswering: true)
        }
        return DetectedEngine(kind: .colima, socketPath: DockerEngineKind.colima.socket(home: home, profile: profile)!,
                              isAnswering: false)
    }
}
