import Foundation

public struct DockerVolume: Identifiable, Sendable, Equatable {
    public let name: String
    public let driver: String
    public let created: Date?
    /// Bytes on disk; nil when the engine hasn't measured it.
    public let size: Int64?
    public let composeProject: String?
    /// Created for a container without a name (`-v /data`), named by a random hash.
    public let isAnonymous: Bool

    public init(name: String, driver: String, created: Date?, size: Int64?, composeProject: String?, isAnonymous: Bool) {
        self.name = name
        self.driver = driver
        self.created = created
        self.size = size
        self.composeProject = composeProject
        self.isAnonymous = isAnonymous
    }

    public var id: String { name }
}
