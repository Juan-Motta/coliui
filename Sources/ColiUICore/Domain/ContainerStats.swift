import Foundation

public struct ContainerStats: Sendable, Equatable {
    public let cpuPercent: Double
    public let memoryBytes: Int64
    public let onlineCPUs: Int
    /// The container's memory limit; the VM's memory when none is set.
    public let memoryLimit: Int64?
    /// Running totals since the container started; rates come from two samples.
    public let networkReceived: Int64
    public let networkSent: Int64
    public let blockRead: Int64
    public let blockWritten: Int64
    /// When the engine took the sample.
    public let sampledAt: Date?

    public init(
        cpuPercent: Double,
        memoryBytes: Int64,
        onlineCPUs: Int = 1,
        memoryLimit: Int64? = nil,
        networkReceived: Int64 = 0,
        networkSent: Int64 = 0,
        blockRead: Int64 = 0,
        blockWritten: Int64 = 0,
        sampledAt: Date? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.onlineCPUs = onlineCPUs
        self.memoryLimit = memoryLimit
        self.networkReceived = networkReceived
        self.networkSent = networkSent
        self.blockRead = blockRead
        self.blockWritten = blockWritten
        self.sampledAt = sampledAt
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
