public protocol ColimaRuntime: Sendable {
    func instances() async throws -> [ColimaInstance]
    func start(profile: String) async throws
    func stop(profile: String) async throws
    func restart(profile: String) async throws
}
