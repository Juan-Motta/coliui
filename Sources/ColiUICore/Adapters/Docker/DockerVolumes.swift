import Foundation

extension DockerEngineRepository: VolumeRepository {
    /// `/volumes` has no sizes; `docker system df` measures them, limited to volumes.
    public func volumes() async throws -> [DockerVolume] {
        let response = try await transport.send(method: "GET", path: "/system/df?type=volume", body: nil)
        try Self.check(response)
        guard let dto = try? JSONDecoder().decode(VolumeListDTO.self, from: response.body) else {
            throw DockerError.malformedResponse
        }
        return (dto.volumes ?? []).map { $0.toDomain() }
    }

    public func createVolume(name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["Name": name, "Driver": "local"], options: [.sortedKeys])
        let response = try await transport.send(method: "POST", path: "/volumes/create", body: body)
        try Self.check(response)
    }

    public func removeVolume(name: String) async throws {
        let name = try Self.validated(name)
        let response = try await transport.send(method: "DELETE", path: "/volumes/\(name)?force=false", body: nil)
        try Self.check(response)
    }
}

private struct VolumeListDTO: Decodable {
    struct Volume: Decodable {
        struct Usage: Decodable {
            let size: Int64
            enum CodingKeys: String, CodingKey { case size = "Size" }
        }
        let name: String
        let driver: String?
        let createdAt: String?
        let labels: [String: String]?
        let usageData: Usage?
        enum CodingKeys: String, CodingKey {
            case name = "Name", driver = "Driver", createdAt = "CreatedAt", labels = "Labels", usageData = "UsageData"
        }

        func toDomain() -> DockerVolume {
            let anonymousName = name.count == 64 && name.allSatisfy(\.isHexDigit)
            return DockerVolume(
                name: name,
                driver: driver ?? "local",
                created: createdAt.flatMap(LogLineParser.parseTimestamp),
                // -1 = not measured.
                size: usageData.flatMap { $0.size >= 0 ? $0.size : nil },
                composeProject: labels?["com.docker.compose.project"],
                isAnonymous: labels?["com.docker.volume.anonymous"] != nil || anonymousName
            )
        }
    }
    let volumes: [Volume]?
    enum CodingKeys: String, CodingKey { case volumes = "Volumes" }
}
