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
