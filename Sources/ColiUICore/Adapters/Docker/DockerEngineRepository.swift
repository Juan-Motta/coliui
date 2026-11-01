import Foundation

/// `ContainerRepository` backed by the Docker Engine REST API.
public struct DockerEngineRepository: ContainerRepository {
    private let transport: HTTPTransport

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

    /// Container IDs and names only use `[A-Za-z0-9_.-]`; anything else could escape the path.
    private static func validated(_ id: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        guard !id.isEmpty, !id.hasPrefix("."), id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DockerError.invalidContainerID
        }
        return id
    }

    private static func check(_ response: HTTPResponse) throws {
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

private struct ContainerDTO: Decodable {
    let id: String
    let names: [String]
    let image: String
    let state: String
    let status: String
    let ports: [PortDTO]?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", names = "Names", image = "Image", state = "State"
        case status = "Status", ports = "Ports", labels = "Labels"
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
            composeProject: labels?["com.docker.compose.project"]
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
