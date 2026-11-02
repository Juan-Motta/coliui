/// One `NAME=value` from a container's environment.
public struct EnvironmentEntry: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Inherited unchanged from the image.
        case image
        /// Set or overridden by the container.
        case container
    }

    public let name: String
    public let value: String
    public let source: Source
    public let isSecret: Bool

    public init(name: String, value: String, source: Source, isSecret: Bool) {
        self.name = name
        self.value = value
        self.source = source
        self.isSecret = isSecret
    }

    /// The container's entries in Docker's order; an entry the image defines identically comes from the image.
    public static func list(container: [String], image: [String]) -> [EnvironmentEntry] {
        let inherited = Set(image)
        return container.map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return EnvironmentEntry(
                name: String(parts[0]),
                value: parts.count > 1 ? String(parts[1]) : "",
                source: inherited.contains(entry) ? .image : .container,
                isSecret: SecretMask.isSecret(entry)
            )
        }
    }
}
