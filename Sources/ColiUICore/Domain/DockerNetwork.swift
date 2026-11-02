import Foundation

public struct DockerNetwork: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let subnet: String?
    public let gateway: String?
    public let composeProject: String?
    /// Containers on it can't reach the internet.
    public let isInternal: Bool

    public init(id: String, name: String, driver: String, subnet: String?, gateway: String?,
                composeProject: String?, isInternal: Bool) {
        self.id = id
        self.name = name
        self.driver = driver
        self.subnet = subnet
        self.gateway = gateway
        self.composeProject = composeProject
        self.isInternal = isInternal
    }

    /// Docker's predefined networks; the engine refuses to remove them.
    public var isBuiltIn: Bool { ["bridge", "host", "none"].contains(name) }
}
