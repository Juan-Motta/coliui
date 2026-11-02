import Foundation

extension DockerEngineRepository: ContainerRunner {
    public func run(_ request: RunRequest) async throws -> String {
        if request.pull { try await pull(request.image) }
        let id: String
        do {
            id = try await create(request)
        } catch DockerError.requestFailed(status: 404, message: _) where !request.pull {
            // Same as `docker run`: fetch a missing image, then try once more.
            try await pull(request.image)
            id = try await create(request)
        }
        try await start(id: id)
        return id
    }

    private func pull(_ image: String) async throws {
        let response = try await transport.send(method: "POST", path: DockerImagePull.path(for: image), body: nil)
        try Self.check(response)
        // Pull failures arrive as {"error": "..."} lines inside a 200 progress stream.
        for line in response.body.split(separator: UInt8(ascii: "\n")) {
            if let progress = try? JSONDecoder().decode(PullProgressDTO.self, from: Data(line)), let error = progress.error {
                throw DockerError.requestFailed(status: response.statusCode, message: error)
            }
        }
    }

    private func create(_ request: RunRequest) async throws -> String {
        var path = "/containers/create"
        if let name = request.name {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
            path += "?name=" + (name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name)
        }
        let body = try JSONSerialization.data(withJSONObject: Self.createBody(request), options: [.sortedKeys])
        let response = try await transport.send(method: "POST", path: path, body: body)
        try Self.check(response)
        guard let created = try? JSONDecoder().decode(CreatedDTO.self, from: response.body) else {
            throw DockerError.malformedResponse
        }
        return created.id
    }

    static func createBody(_ request: RunRequest) -> [String: Any] {
        var exposed: [String: [String: String]] = [:]
        var bindings: [String: [[String: String]]] = [:]
        for port in request.ports {
            let key = "\(port.containerPort)/\(port.proto)"
            exposed[key] = [:]
            bindings[key, default: []].append(["HostPort": port.hostPort.map(String.init) ?? ""])
        }
        let home = NSHomeDirectory()
        let binds = request.volumes.map { volume in
            // Only `~` and `~/…` are our home; `~other` stays as typed.
            let source = volume.source == "~" || volume.source.hasPrefix("~/") ? home + volume.source.dropFirst() : volume.source
            return "\(source):\(volume.target)"
        }
        return [
            "Image": request.image,
            "Env": request.environment.map { "\($0.key)=\($0.value)" },
            "ExposedPorts": exposed,
            "HostConfig": [
                "PortBindings": bindings,
                "Binds": binds,
                "AutoRemove": request.autoRemove,
                "RestartPolicy": ["Name": request.restartPolicy.rawValue],
            ] as [String: Any],
        ]
    }
}

private struct PullProgressDTO: Decodable {
    let error: String?
}

private struct CreatedDTO: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey { case id = "Id" }
}
