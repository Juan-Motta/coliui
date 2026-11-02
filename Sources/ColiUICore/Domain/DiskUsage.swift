import Foundation

public struct DiskCategory: Sendable, Equatable {
    public let totalBytes: Int64
    public let reclaimableBytes: Int64
    /// Names of what a prune would remove (image tags, container or volume names, cache IDs).
    public let reclaimableItems: [String]

    public init(totalBytes: Int64, reclaimableBytes: Int64, reclaimableItems: [String]) {
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
        self.reclaimableItems = reclaimableItems
    }
}

/// What Docker stores inside the Colima VM, from `docker system df`.
public struct DiskUsage: Sendable, Equatable {
    public let images: DiskCategory
    public let containers: DiskCategory
    public let volumes: DiskCategory
    public let buildCache: DiskCategory

    public init(images: DiskCategory, containers: DiskCategory, volumes: DiskCategory, buildCache: DiskCategory) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
        self.buildCache = buildCache
    }

    public var totalBytes: Int64 {
        images.totalBytes + containers.totalBytes + volumes.totalBytes + buildCache.totalBytes
    }

    public func category(_ target: PruneTarget) -> DiskCategory {
        switch target {
        case .images: images
        case .containers: containers
        case .volumes: volumes
        case .buildCache: buildCache
        }
    }
}

public enum PruneTarget: String, CaseIterable, Sendable {
    case images, containers, volumes, buildCache
}

public enum ByteFormat {
    /// Decimal units like Finder: "4 KB", "120 MB", "1.7 GB".
    public static func short(_ bytes: Int64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<1_000: return "\(bytes) B"
        case ..<1_000_000: return "\(Int((value / 1_000).rounded())) KB"
        case ..<1_000_000_000: return "\(Int((value / 1_000_000).rounded())) MB"
        default: return String(format: "%.1f GB", value / 1_000_000_000)
        }
    }
}
