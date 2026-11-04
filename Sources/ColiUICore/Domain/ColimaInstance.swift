import Foundation

public enum ColimaStatus: Sendable, Equatable {
    case running
    case stopped
    case other(String)

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "running": self = .running
        case "stopped": self = .stopped
        default: self = .other(rawValue)
        }
    }
}

public struct ColimaResourceUsage: Sendable, Equatable {
    public let cpuPercent: Double
    public let memoryUsedBytes: Int64
    public let memoryTotalBytes: Int64
    public let diskUsedBytes: Int64
    public let diskTotalBytes: Int64

    public init(cpuPercent: Double, memoryUsedBytes: Int64, memoryTotalBytes: Int64, diskUsedBytes: Int64 = 0, diskTotalBytes: Int64 = 0) {
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
    }

    /// The last line of `ColimaCLIRuntime.resourceScript`: "12.50 used total diskUsed diskTotal".
    public static func parse(_ output: String) -> ColimaResourceUsage? {
        guard let line = output.split(whereSeparator: \.isNewline).last else { return nil }
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 5, let cpu = Double(fields[0]), let used = Int64(fields[1]), let total = Int64(fields[2]),
              let diskUsed = Int64(fields[3]), let diskTotal = Int64(fields[4]), total > 0, diskTotal > 0
        else { return nil }
        return ColimaResourceUsage(cpuPercent: min(max(cpu, 0), 100), memoryUsedBytes: used, memoryTotalBytes: total,
                                   diskUsedBytes: diskUsed, diskTotalBytes: diskTotal)
    }

    /// Memory used, 0…1.
    public var memoryLevel: Double { Double(memoryUsedBytes) / Double(max(memoryTotalBytes, 1)) }
    /// Disk used, 0…1.
    public var diskLevel: Double { min(max(Double(diskUsedBytes) / Double(max(diskTotalBytes, 1)), 0), 1) }

    public var cpuDisplay: String { String(format: "%.0f%%", cpuPercent) }
    public var memoryDisplay: String {
        "\(ByteFormat.binary(memoryUsedBytes)) / \(ByteFormat.binary(memoryTotalBytes))"
    }
}

public struct ColimaInstance: Identifiable, Sendable, Equatable {
    public let name: String
    public let status: ColimaStatus
    public let arch: String
    public let cpus: Int
    public let memoryBytes: Int64
    public let diskBytes: Int64
    public let runtime: String
    /// "vz" or "qemu"; only known while the VM is running.
    public let vmType: String?

    public init(
        name: String,
        status: ColimaStatus,
        arch: String,
        cpus: Int,
        memoryBytes: Int64,
        diskBytes: Int64,
        runtime: String,
        vmType: String? = nil
    ) {
        self.vmType = vmType
        self.name = name
        self.status = status
        self.arch = arch
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
        self.runtime = runtime
    }

    public var id: String { name }
    public var isRunning: Bool { status == .running }

    public var memoryDisplay: String { Self.gib(memoryBytes) }
    public var diskDisplay: String { Self.gib(diskBytes) }

    /// "4 CPU · 4 GiB · 100 GiB"
    public var resourcesSummary: String {
        "\(cpus) CPU · \(memoryDisplay) · \(diskDisplay)"
    }

    static func gib(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return value.rounded() == value ? "\(Int(value)) GiB" : String(format: "%.1f GiB", value)
    }
}
