import Foundation

/// The editable part of a Colima profile (`~/.colima/<profile>/colima.yaml`).
public struct ColimaProfileSettings: Sendable, Equatable {
    public var cpus: Int
    public var memoryGiB: Double
    public var diskGiB: Int
    /// vz, qemu or krunkit; fixed once the VM exists.
    public var vmType: String
    public var mountType: String
    /// Rosetta x86 emulation; vz only.
    public var rosetta: Bool
    /// docker, containerd or incus; fixed once the VM exists.
    public var runtime: String

    public init(cpus: Int, memoryGiB: Double, diskGiB: Int, vmType: String, mountType: String, rosetta: Bool, runtime: String) {
        self.cpus = cpus
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
        self.vmType = vmType
        self.mountType = mountType
        self.rosetta = rosetta
        self.runtime = runtime
    }

    /// Colima's defaults for a new profile.
    public static let newProfile = ColimaProfileSettings(
        cpus: 2, memoryGiB: 2, diskGiB: 100, vmType: "vz", mountType: "virtiofs", rosetta: false, runtime: "docker"
    )

    /// Reads the top-level keys ColiUI edits; anything missing takes Colima's default.
    public init?(yaml: String) {
        var values: [String: String] = [:]
        for line in yaml.split(whereSeparator: \.isNewline) {
            guard let first = line.first, !first.isWhitespace, first != "#", let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        guard !values.isEmpty else { return nil }
        let defaults = Self.newProfile
        self.init(
            cpus: values["cpu"].flatMap(Int.init) ?? defaults.cpus,
            memoryGiB: values["memory"].flatMap(Double.init) ?? defaults.memoryGiB,
            diskGiB: values["disk"].flatMap(Int.init) ?? defaults.diskGiB,
            vmType: values["vmType"].flatMap { $0.isEmpty ? nil : $0 } ?? defaults.vmType,
            mountType: values["mountType"].flatMap { $0.isEmpty ? nil : $0 } ?? defaults.mountType,
            rosetta: values["rosetta"] == "true",
            runtime: values["runtime"].flatMap { $0.isEmpty ? nil : $0 } ?? defaults.runtime
        )
    }

    /// `--cpus 2 --memory 2.5 --disk 100 --mount-type virtiofs [--vz-rosetta=…]`
    var resourceArguments: [String] {
        let memory = memoryGiB.rounded() == memoryGiB ? String(Int(memoryGiB)) : String(memoryGiB)
        var arguments = ["--cpus", "\(cpus)", "--memory", memory, "--disk", "\(diskGiB)", "--mount-type", mountType]
        if vmType == "vz" { arguments.append("--vz-rosetta=\(rosetta)") }
        return arguments
    }
}
