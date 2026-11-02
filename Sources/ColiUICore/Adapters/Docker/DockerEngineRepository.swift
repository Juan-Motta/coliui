import Foundation

/// `ContainerRepository` backed by the Docker Engine REST API.
public struct DockerEngineRepository: ContainerRepository, ContainerInspector, ContainerEnvironmentSource, DockerInventory {
    let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func listContainers() async throws -> [Container] {
        let response = try await transport.send(method: "GET", path: "/containers/json?all=1", body: nil)
        try Self.check(response)
        do {
            return try JSONDecoder().decode([ContainerDTO].self, from: response.body).map { $0.toDomain() }
        } catch {
            throw DockerError.malformedResponse
        }
    }

    /// `stream=false` makes the engine take two samples (~1 s apart) so CPU deltas are meaningful.
    public func stats(id: String) async throws -> ContainerStats {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "GET", path: "/containers/\(id)/stats?stream=false", body: nil)
        try Self.check(response)
        guard let dto = try? JSONDecoder().decode(StatsDTO.self, from: response.body) else {
            throw DockerError.malformedResponse
        }
        return dto.toDomain()
    }

    public func summary() async throws -> DockerSummary {
        async let images = decodeList(path: "/images/json")
        async let volumes = decode(VolumesDTO.self, path: "/volumes")
        async let networks = decodeList(path: "/networks")
        return try await DockerSummary(images: images, volumes: volumes.volumes?.count ?? 0, networks: networks)
    }

    private func decodeList(path: String) async throws -> Int {
        try await decode([IgnoredDTO].self, path: path).count
    }

    private func decode<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let response = try await transport.send(method: "GET", path: path, body: nil)
        try Self.check(response)
        guard let value = try? JSONDecoder().decode(type, from: response.body) else { throw DockerError.malformedResponse }
        return value
    }

    public func start(id: String) async throws {
        try await post(id: id, action: "start")
    }

    public func stop(id: String) async throws {
        try await post(id: id, action: "stop")
    }

    public func restart(id: String) async throws {
        try await post(id: id, action: "restart")
    }

    public func remove(id: String, force: Bool) async throws {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "DELETE", path: "/containers/\(id)?force=\(force)", body: nil)
        try Self.check(response)
    }

    private func post(id: String, action: String) async throws {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "POST", path: "/containers/\(id)/\(action)", body: nil)
        try Self.check(response)
    }

    public func details(id: String) async throws -> ContainerDetails {
        let id = try Self.validated(id)
        return try await decode(InspectDTO.self, path: "/containers/\(id)/json").toDomain()
    }

    public func inspect(id: String) async throws -> JSONValue {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "GET", path: "/containers/\(id)/json", body: nil)
        try Self.check(response)
        return Self.maskingEnvSecrets(try JSONValue.parse(response.body))
    }

    public func environment(id: String) async throws -> [EnvironmentEntry] {
        let id = try Self.validated(id)
        let container = try await decode(EnvironmentDTO.self, path: "/containers/\(id)/json")
        var image: [String] = []
        // Image IDs are `sha256:<hex>`; anything else stays out of the path. A missing image leaves `image` empty.
        if let imageID = container.image, imageID.wholeMatch(of: /sha256:[0-9a-f]{12,64}/) != nil {
            image = (try? await decode(EnvironmentDTO.self, path: "/images/\(imageID)/json"))?.config?.env ?? []
        }
        return EnvironmentEntry.list(container: container.config?.env ?? [], image: image)
    }

    /// Masks the entries of the top-level `Config.Env`, the only place Docker puts the environment.
    static func maskingEnvSecrets(_ value: JSONValue) -> JSONValue {
        guard case .object(let members) = value else { return value }
        return .object(members.map { member in
            guard member.key == "Config", case .object(let config) = member.value else { return member }
            return JSONMember(key: "Config", value: .object(config.map { entry in
                guard entry.key == "Env", case .array(let items) = entry.value else { return entry }
                return JSONMember(key: "Env", value: .array(items.map { item in
                    if case .string(let text) = item { return .string(SecretMask.masked(text)) }
                    return item
                }))
            }))
        })
    }

    /// `CharacterSet.alphanumerics` also admits letters and digits of other scripts (é, ٣).
    static let asciiAlphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Container IDs and names only use `[A-Za-z0-9_.-]`; anything else could escape the path.
    static func validated(_ id: String) throws -> String {
        let allowed = asciiAlphanumerics.union(CharacterSet(charactersIn: "_.-"))
        guard !id.isEmpty, !id.hasPrefix("."), id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DockerError.invalidContainerID
        }
        return id
    }

    static func check(_ response: HTTPResponse) throws {
        // 304 = already started/stopped; the desired state holds.
        if (200..<300).contains(response.statusCode) || response.statusCode == 304 { return }
        let message = (try? JSONDecoder().decode(EngineErrorDTO.self, from: response.body))?.message
            ?? "Docker request failed (HTTP \(response.statusCode))."
        throw DockerError.requestFailed(status: response.statusCode, message: message)
    }
}

private struct EngineErrorDTO: Decodable {
    let message: String
}

private struct IgnoredDTO: Decodable {}

private struct InspectDTO: Decodable {
    struct ConfigDTO: Decodable {
        let image: String
        let tty: Bool?
        let env: [String]?
        enum CodingKeys: String, CodingKey { case image = "Image", tty = "Tty", env = "Env" }
    }
    struct HostConfigDTO: Decodable {
        struct RestartPolicyDTO: Decodable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name = "Name" }
        }
        let restartPolicy: RestartPolicyDTO?
        enum CodingKeys: String, CodingKey { case restartPolicy = "RestartPolicy" }
    }
    struct NetworkSettingsDTO: Decodable {
        struct NetworkDTO: Decodable {
            let ipAddress: String?
            enum CodingKeys: String, CodingKey { case ipAddress = "IPAddress" }
        }
        let networks: [String: NetworkDTO]?
        enum CodingKeys: String, CodingKey { case networks = "Networks" }
    }
    struct MountDTO: Decodable {
        let type: String?
        let name: String?
        let source: String?
        let destination: String
        enum CodingKeys: String, CodingKey {
            case type = "Type", name = "Name", source = "Source", destination = "Destination"
        }
    }

    let id: String
    let name: String
    let created: String?
    let config: ConfigDTO
    let hostConfig: HostConfigDTO?
    let networkSettings: NetworkSettingsDTO?
    let mounts: [MountDTO]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", created = "Created", config = "Config"
        case hostConfig = "HostConfig", networkSettings = "NetworkSettings", mounts = "Mounts"
    }

    func toDomain() -> ContainerDetails {
        let network = networkSettings?.networks?.sorted { $0.key < $1.key }.first
        let ip = network?.value.ipAddress.flatMap { $0.isEmpty ? nil : $0 }
        let policy = hostConfig?.restartPolicy?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "no"
        return ContainerDetails(
            id: id,
            name: name.hasPrefix("/") ? String(name.dropFirst()) : name,
            image: config.image,
            created: created.flatMap(LogLineParser.parseTimestamp),
            restartPolicy: policy,
            network: network?.key,
            ipAddress: ip,
            mounts: (mounts ?? []).map { mount in
                // Named volumes read better by name than by their path inside the VM.
                let source = mount.type == "volume" ? (mount.name ?? mount.source ?? "") : (mount.source ?? "")
                return ContainerMount(source: source, destination: mount.destination)
            },
            environment: config.env ?? [],
            tty: config.tty ?? false
        )
    }
}

/// The parts of a container or image inspect that hold the environment.
private struct EnvironmentDTO: Decodable {
    struct ConfigDTO: Decodable {
        let env: [String]?
        enum CodingKeys: String, CodingKey { case env = "Env" }
    }
    let image: String?
    let config: ConfigDTO?
    enum CodingKeys: String, CodingKey { case image = "Image", config = "Config" }
}

private struct VolumesDTO: Decodable {
    let volumes: [IgnoredDTO]?
    enum CodingKeys: String, CodingKey { case volumes = "Volumes" }
}

private struct StatsDTO: Decodable {
    struct CPU: Decodable {
        struct Usage: Decodable { let total_usage: Int64 }
        let cpu_usage: Usage
        let system_cpu_usage: Int64?
        let online_cpus: Int?
    }
    struct Memory: Decodable {
        let usage: Int64?
        let limit: Int64?
        let stats: [String: Int64]?
    }
    struct Network: Decodable {
        let rx_bytes: Int64
        let tx_bytes: Int64
    }
    struct BlockIO: Decodable {
        struct Entry: Decodable { let op: String; let value: Int64 }
        let io_service_bytes_recursive: [Entry]?
    }
    let read: String?
    let cpu_stats: CPU
    let precpu_stats: CPU
    let memory_stats: Memory
    let networks: [String: Network]?
    let blkio_stats: BlockIO?

    /// Same formulas as `docker stats` on Linux (cgroup v2 reports page cache as `inactive_file`).
    func toDomain() -> ContainerStats {
        let cpuDelta = Double(cpu_stats.cpu_usage.total_usage - precpu_stats.cpu_usage.total_usage)
        let systemDelta = Double((cpu_stats.system_cpu_usage ?? 0) - (precpu_stats.system_cpu_usage ?? 0))
        let cpus = cpu_stats.online_cpus ?? 1
        let cpu = cpuDelta > 0 && systemDelta > 0 ? cpuDelta / systemDelta * Double(cpus) * 100 : 0
        let cache = memory_stats.stats?["inactive_file"] ?? memory_stats.stats?["total_inactive_file"] ?? 0
        let memory = max((memory_stats.usage ?? 0) - cache, 0)
        let io = blkio_stats?.io_service_bytes_recursive ?? []
        func blockTotal(_ op: String) -> Int64 {
            io.filter { $0.op.lowercased() == op }.reduce(0) { $0 + $1.value }
        }
        let networks = (networks ?? [:]).values
        return ContainerStats(
            cpuPercent: cpu,
            memoryBytes: memory,
            onlineCPUs: cpus,
            memoryLimit: memory_stats.limit.flatMap { $0 > 0 ? $0 : nil },
            networkReceived: networks.reduce(0) { $0 + $1.rx_bytes },
            networkSent: networks.reduce(0) { $0 + $1.tx_bytes },
            blockRead: blockTotal("read"),
            blockWritten: blockTotal("write"),
            sampledAt: read.flatMap(LogLineParser.parseTimestamp)
        )
    }
}

private struct ContainerDTO: Decodable {
    let id: String
    let names: [String]
    let image: String
    let imageID: String?
    let state: String
    let status: String
    let ports: [PortDTO]?
    let labels: [String: String]?
    let mounts: [MountDTO]?
    let networkSettings: NetworkSettingsDTO?

    struct MountDTO: Decodable {
        let type: String?
        let name: String?
        enum CodingKeys: String, CodingKey { case type = "Type", name = "Name" }
    }

    struct NetworkSettingsDTO: Decodable {
        let networks: [String: IgnoredDTO]?
        enum CodingKeys: String, CodingKey { case networks = "Networks" }
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id", names = "Names", image = "Image", imageID = "ImageID", state = "State"
        case status = "Status", ports = "Ports", labels = "Labels", mounts = "Mounts", networkSettings = "NetworkSettings"
    }

    func toDomain() -> Container {
        let name = names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(id.prefix(12))
        // The engine lists IPv4 and IPv6 bindings separately; show each mapping once.
        var seen = Set<PortMapping>()
        let mappings = (ports ?? [])
            .map { PortMapping(privatePort: $0.privatePort, publicPort: $0.publicPort, proto: $0.type) }
            .filter { seen.insert($0).inserted }
            .sorted { ($0.publicPort ?? .max, $0.privatePort) < ($1.publicPort ?? .max, $1.privatePort) }
        return Container(
            id: id,
            name: name,
            image: image,
            state: ContainerState(rawValue: state) ?? .unknown,
            status: status,
            ports: mappings,
            composeProject: labels?["com.docker.compose.project"],
            composeService: labels?["com.docker.compose.service"],
            composeConfigFile: labels?["com.docker.compose.project.config_files"]?
                .split(separator: ",").first.map(String.init),
            imageID: imageID,
            volumeNames: (mounts ?? []).filter { $0.type == "volume" }.compactMap(\.name),
            networkNames: (networkSettings?.networks?.keys).map { $0.sorted() } ?? []
        )
    }
}

private struct PortDTO: Decodable {
    let privatePort: Int
    let publicPort: Int?
    let type: String

    enum CodingKeys: String, CodingKey {
        case privatePort = "PrivatePort", publicPort = "PublicPort", type = "Type"
    }
}
