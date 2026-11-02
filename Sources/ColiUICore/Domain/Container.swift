import Foundation

public enum ContainerState: String, Sendable, Equatable {
    case created, running, paused, restarting, removing, exited, dead, unknown
}

public struct PortMapping: Sendable, Hashable {
    public let privatePort: Int
    public let publicPort: Int?
    public let proto: String

    public init(privatePort: Int, publicPort: Int?, proto: String) {
        self.privatePort = privatePort
        self.publicPort = publicPort
        self.proto = proto
    }

    /// "8080→80" when published on the host, "80/tcp" when only exposed.
    public var display: String {
        if let publicPort { return "\(publicPort)→\(privatePort)" }
        return "\(privatePort)/\(proto)"
    }

    public var localURL: URL? {
        guard let publicPort, proto == "tcp" else { return nil }
        return URL(string: "http://localhost:\(publicPort)")
    }
}

public struct Container: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let image: String
    public let state: ContainerState
    public let status: String
    public let ports: [PortMapping]
    public let composeProject: String?
    public let composeService: String?
    /// First file of `com.docker.compose.project.config_files`.
    public let composeConfigFile: String?
    /// "sha256:…" of the image the container was created from.
    public let imageID: String?

    public init(
        id: String,
        name: String,
        image: String,
        state: ContainerState,
        status: String,
        ports: [PortMapping] = [],
        composeProject: String? = nil,
        composeService: String? = nil,
        composeConfigFile: String? = nil,
        imageID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.composeProject = composeProject
        self.composeService = composeService
        self.composeConfigFile = composeConfigFile
        self.imageID = imageID
    }

    public var shortID: String { String(id.prefix(12)) }
    public var isRunning: Bool { state == .running }
    public var portsDisplay: String {
        ports.isEmpty ? "—" : ports.map(\.display).joined(separator: ", ")
    }
}
