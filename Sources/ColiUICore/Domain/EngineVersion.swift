public struct EngineVersion: Sendable, Equatable {
    public let version: String
    public let apiVersion: String

    public init(version: String, apiVersion: String) {
        self.version = version
        self.apiVersion = apiVersion
    }
}
