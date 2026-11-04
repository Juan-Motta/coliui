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
    private(set) var resourceUsage: ColimaResourceUsage?
    /// The menu bar charts: CPU and memory, 0…1, oldest first.
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    static let historyLength = 24
    private(set) var profileCount = 0
    private(set) var pendingAction: ColimaAction?
    var errorMessage: String?
    let profile: String
    /// True after the user stops the VM, so that stop isn't reported as unexpected.
    private(set) var stoppedByUser = false
    /// Called after every successful refresh, and when a start fails (Settings › Notifications).
    var onRefresh: ((ColimaViewModel) -> Void)?
    var onStartFailed: ((String) -> Void)?

    private let runtime: ColimaRuntime

    init(runtime: ColimaRuntime, profile: String) {
        self.runtime = runtime
        self.profile = profile
    }

    var isBusy: Bool { pendingAction != nil }
    var isRunning: Bool { instance?.isRunning ?? false }

    /// One sample for the menu bar; a stopped VM clears the charts so an old curve doesn't return on start.
    func refreshResourceUsage() async {
        guard isRunning else {
            resourceUsage = nil
            cpuHistory = []
            memoryHistory = []
            return
        }
        resourceUsage = try? await runtime.resourceUsage(profile: profile)
        guard let resourceUsage else { return }
        cpuHistory = Array((cpuHistory + [resourceUsage.cpuPercent / 100]).suffix(Self.historyLength))
        memoryHistory = Array((memoryHistory + [resourceUsage.memoryLevel]).suffix(Self.historyLength))
    }

    func refresh() async {
        do {
            let instances = try await runtime.instances()
            profileCount = instances.count
            instance = instances.first { $0.name == profile }
            errorMessage = instance == nil
                ? "Colima profile “\(profile)” not found. Start it with `colima start`."
                : nil
            if isRunning { stoppedByUser = false }
            onRefresh?(self)
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
            if action == .start { onStartFailed?(error.localizedDescription) }
            return
        }
        if action == .stop { stoppedByUser = true }
        await refresh()
    }
}
