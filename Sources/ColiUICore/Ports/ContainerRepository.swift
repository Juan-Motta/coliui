public protocol ContainerRepository: Sendable {
    func listContainers() async throws -> [Container]
    func start(id: String) async throws
    func stop(id: String) async throws
    func restart(id: String) async throws
    func remove(id: String, force: Bool) async throws
}
