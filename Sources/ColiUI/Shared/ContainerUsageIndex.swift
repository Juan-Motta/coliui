import ColiUICore

/// Container names by key (image ID, volume or network name), rebuilt only when the container list changes.
/// Every row of Images, Volumes and Networks asks "who uses this?"; scanning all containers per row and
/// per render added up. Comparing an unchanged array is cheap: Swift checks the shared buffer first.
struct ContainerUsageIndex {
    private let keys: (Container) -> [String]
    private var indexed: [Container]?
    private var names: [String: [String]] = [:]

    init(keys: @escaping (Container) -> [String]) {
        self.keys = keys
    }

    /// Names in natural order, for the containers given.
    mutating func names(for key: String, in containers: [Container]) -> [String] {
        if indexed != containers {
            var built: [String: [String]] = [:]
            for container in containers {
                for key in keys(container) { built[key, default: []].append(container.name) }
            }
            names = built.mapValues { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
            indexed = containers
        }
        return names[key] ?? []
    }
}
