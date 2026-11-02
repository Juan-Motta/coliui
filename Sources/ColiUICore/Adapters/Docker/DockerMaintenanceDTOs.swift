import Foundation

extension DockerEngineRepository: DockerMaintenance {
    public func diskUsage() async throws -> DiskUsage {
        try await decode(SystemDFDTO.self, path: "/system/df").toDomain()
    }

    public func prune(_ target: PruneTarget) async throws -> Int64 {
        let response = try await transport.send(method: "POST", path: Self.prunePath(target), body: nil)
        try Self.check(response)
        return (try? JSONDecoder().decode(PruneDTO.self, from: response.body))?.spaceReclaimed ?? 0
    }

    static func prunePath(_ target: PruneTarget) -> String {
        func filters(_ json: String) -> String {
            "?filters=" + json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        }
        return switch target {
        // dangling=false: every image no container uses, not only untagged layers.
        case .images: "/images/prune" + filters(#"{"dangling":["false"]}"#)
        case .containers: "/containers/prune"
        // all=true: named volumes too (API ≥ 1.42 prunes only anonymous ones by default).
        case .volumes: "/volumes/prune" + filters(#"{"all":["true"]}"#)
        case .buildCache: "/build/prune?all=1"
        }
    }
}

private struct PruneDTO: Decodable {
    let spaceReclaimed: Int64?
    enum CodingKeys: String, CodingKey { case spaceReclaimed = "SpaceReclaimed" }
}

private struct UsageDTO: Decodable {
    let totalSize: Int64?
    let reclaimable: Int64?
    enum CodingKeys: String, CodingKey { case totalSize = "TotalSize", reclaimable = "Reclaimable" }
}

private struct SystemDFDTO: Decodable {
    struct Image: Decodable {
        let id: String
        let repoTags: [String]?
        let size: Int64
        let sharedSize: Int64
        let containers: Int
        enum CodingKeys: String, CodingKey {
            case id = "Id", repoTags = "RepoTags", size = "Size", sharedSize = "SharedSize", containers = "Containers"
        }
    }
    struct Container: Decodable {
        let names: [String]
        let state: String
        let sizeRw: Int64?
        enum CodingKeys: String, CodingKey { case names = "Names", state = "State", sizeRw = "SizeRw" }
    }
    struct Volume: Decodable {
        struct Usage: Decodable {
            let refCount: Int
            let size: Int64
            enum CodingKeys: String, CodingKey { case refCount = "RefCount", size = "Size" }
        }
        let name: String
        let usageData: Usage?
        enum CodingKeys: String, CodingKey { case name = "Name", usageData = "UsageData" }
    }
    struct Cache: Decodable {
        let id: String
        let size: Int64
        let inUse: Bool
        enum CodingKeys: String, CodingKey { case id = "ID", size = "Size", inUse = "InUse" }
    }

    let layersSize: Int64?
    let images: [Image]?
    let containers: [Container]?
    let volumes: [Volume]?
    let buildCache: [Cache]?
    let imageUsage: UsageDTO?
    let containerUsage: UsageDTO?
    let volumeUsage: UsageDTO?
    let buildCacheUsage: UsageDTO?

    enum CodingKeys: String, CodingKey {
        case layersSize = "LayersSize", images = "Images", containers = "Containers", volumes = "Volumes"
        case buildCache = "BuildCache", imageUsage = "ImageUsage", containerUsage = "ContainerUsage"
        case volumeUsage = "VolumeUsage", buildCacheUsage = "BuildCacheUsage"
    }

    /// Prefers the engine's own totals (API ≥ 1.52) and computes them from the item lists otherwise.
    func toDomain() -> DiskUsage {
        let images = images ?? []
        let unusedImages = images.filter { $0.containers == 0 }
        let stopped = (containers ?? []).filter { $0.state != "running" }
        let orphanVolumes = (volumes ?? []).filter { ($0.usageData?.refCount ?? 1) == 0 }
        let idleCache = (buildCache ?? []).filter { !$0.inUse }

        return DiskUsage(
            images: DiskCategory(
                totalBytes: imageUsage?.totalSize ?? layersSize ?? images.reduce(0) { $0 + $1.size },
                reclaimableBytes: imageUsage?.reclaimable ?? unusedImages.reduce(0) { $0 + $1.size - max($1.sharedSize, 0) },
                reclaimableItems: unusedImages.map(Self.imageName)
            ),
            containers: DiskCategory(
                totalBytes: containerUsage?.totalSize ?? (containers ?? []).reduce(0) { $0 + ($1.sizeRw ?? 0) },
                reclaimableBytes: containerUsage?.reclaimable ?? stopped.reduce(0) { $0 + ($1.sizeRw ?? 0) },
                reclaimableItems: stopped.compactMap { $0.names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } }
            ),
            volumes: DiskCategory(
                totalBytes: volumeUsage?.totalSize ?? (volumes ?? []).reduce(0) { $0 + max($1.usageData?.size ?? 0, 0) },
                reclaimableBytes: volumeUsage?.reclaimable ?? orphanVolumes.reduce(0) { $0 + max($1.usageData?.size ?? 0, 0) },
                reclaimableItems: orphanVolumes.map(\.name)
            ),
            buildCache: DiskCategory(
                totalBytes: buildCacheUsage?.totalSize ?? (buildCache ?? []).reduce(0) { $0 + $1.size },
                reclaimableBytes: buildCacheUsage?.reclaimable ?? idleCache.reduce(0) { $0 + $1.size },
                reclaimableItems: idleCache.map { String($0.id.prefix(12)) }
            )
        )
    }

    private static func imageName(_ image: Image) -> String {
        if let tag = image.repoTags?.first(where: { $0 != "<none>:<none>" }) { return tag }
        let id = image.id.hasPrefix("sha256:") ? String(image.id.dropFirst(7)) : image.id
        return "<none> \(id.prefix(12))"
    }
}
