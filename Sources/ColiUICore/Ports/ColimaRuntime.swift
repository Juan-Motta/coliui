public protocol ColimaRuntime: Sendable {
    func instances() async throws -> [ColimaInstance]
    func resourceUsage(profile: String) async throws -> ColimaResourceUsage?
    func start(profile: String) async throws
    func stop(profile: String) async throws
    func restart(profile: String) async throws
    func settings(profile: String) async throws -> ColimaProfileSettings
    /// Restarts the profile with new resources (stopping it first when running).
    func apply(_ settings: ColimaProfileSettings, to profile: String, isRunning: Bool) async throws
    func create(profile: String, settings: ColimaProfileSettings) async throws
    func delete(profile: String) async throws
}

public extension ColimaRuntime {
    func resourceUsage(profile: String) async throws -> ColimaResourceUsage? { nil }
}
