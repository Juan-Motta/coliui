import ColiUICore
import Foundation
import Observation

enum ColimaAction {
    case start, stop, restart

    var progressTitle: String {
        switch self {
        case .start: "Starting…"
        case .stop: "Stopping…"
        case .restart: "Restarting…"
        }
    }
}

@MainActor
@Observable
final class ColimaViewModel {
    private(set) var instance: ColimaInstance?
    private(set) var profileCount = 0
    private(set) var pendingAction: ColimaAction?
    var errorMessage: String?
    let profile: String

    private let runtime: ColimaRuntime

    init(runtime: ColimaRuntime, profile: String) {
        self.runtime = runtime
        self.profile = profile
    }

    var isBusy: Bool { pendingAction != nil }
    var isRunning: Bool { instance?.isRunning ?? false }

    func refresh() async {
        do {
            let instances = try await runtime.instances()
            profileCount = instances.count
            instance = instances.first { $0.name == profile }
            errorMessage = instance == nil
                ? "Colima profile “\(profile)” not found. Start it with `colima start`."
                : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Settings › Start Colima when ColiUI opens. Only an existing, stopped profile:
    /// `colima start` would create a new VM for a missing one.
    func startIfStopped() async {
        guard let instance, instance.status == .stopped, !isBusy else { return }
        await perform(.start)
    }

    func perform(_ action: ColimaAction) async {
        pendingAction = action
        defer { pendingAction = nil }
        do {
            switch action {
            case .start: try await runtime.start(profile: profile)
            case .stop: try await runtime.stop(profile: profile)
            case .restart: try await runtime.restart(profile: profile)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
    }
}
