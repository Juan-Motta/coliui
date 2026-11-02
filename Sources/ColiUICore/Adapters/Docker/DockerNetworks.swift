import Foundation

extension DockerEngineRepository: NetworkRepository {
    public func networks() async throws -> [DockerNetwork] {
        let response = try await transport.send(method: "GET", path: "/networks", body: nil)
        try Self.check(response)
        guard let dtos = try? JSONDecoder().decode([NetworkDTO].self, from: response.body) else {
            throw DockerError.malformedResponse
        }
        return dtos.map { $0.toDomain() }
    }

    public func createNetwork(name: String, driver: String, internal: Bool) async throws {
        let payload: [String: Any] = ["Name": name, "Driver": driver, "Internal": `internal`]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let response = try await transport.send(method: "POST", path: "/networks/create", body: body)
        try Self.check(response)
    }

    public func removeNetwork(id: String) async throws {
        let id = try Self.validated(id)
        let response = try await transport.send(method: "DELETE", path: "/networks/\(id)", body: nil)
        try Self.check(response)
    }
}

private struct NetworkDTO: Decodable {
    struct IPAM: Decodable {
        struct Config: Decodable {
            let subnet: String?
            let gateway: String?
            enum CodingKeys: String, CodingKey { case subnet = "Subnet", gateway = "Gateway" }
        }
        let config: [Config]?
        enum CodingKeys: String, CodingKey { case config = "Config" }
    }
    let id: String
    let name: String
    let driver: String?
    let isInternal: Bool?
    let ipam: IPAM?
    let labels: [String: String]?
    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", driver = "Driver", isInternal = "Internal", ipam = "IPAM", labels = "Labels"
    }

    func toDomain() -> DockerNetwork {
        // The first config is IPv4 unless the network is IPv6-only.
        let config = ipam?.config?.first
        return DockerNetwork(
            id: id,
            name: name,
            driver: driver ?? "bridge",
            subnet: config?.subnet.flatMap { $0.isEmpty ? nil : $0 },
            gateway: config?.gateway.flatMap { $0.isEmpty ? nil : $0 },
            composeProject: labels?["com.docker.compose.project"],
            isInternal: isInternal ?? false
        )
    }
}
