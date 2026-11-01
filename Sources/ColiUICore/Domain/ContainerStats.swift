import Foundation

public struct ContainerStats: Sendable, Equatable {
    public let cpuPercent: Double
    public let memoryBytes: Int64

    public init(cpuPercent: Double, memoryBytes: Int64) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    /// "3.1%"
    public var cpuDisplay: String { String(format: "%.1f%%", cpuPercent) }

    /// "214 MiB" below 1 GiB, "1.5 GiB" above.
    public var memoryDisplay: String {
        let mib = Double(memoryBytes) / 1_048_576
        if mib < 1024 { return "\(Int(mib.rounded())) MiB" }
        return String(format: "%.1f GiB", mib / 1024)
    }
}

/// Totals shown next to the sidebar sections.
public struct DockerSummary: Sendable, Equatable {
    public let images: Int
    public let volumes: Int
    public let networks: Int

    public init(images: Int, volumes: Int, networks: Int) {
        self.images = images
        self.volumes = volumes
        self.networks = networks
    }
}
