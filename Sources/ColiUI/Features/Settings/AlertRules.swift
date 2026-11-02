import ColiUICore
import Foundation

struct Alert: Equatable {
    let kind: NotificationKind
    let title: String
    let body: String
    let identifier: String
}

/// Settings › Notifications: turns what the app observes into alerts. Pure; the app decides which kinds to deliver.
struct AlertRules {
    static let diskIdentifier = "disk-almost-full"
    private static let loopWindow: TimeInterval = 5 * 60
    private static let loopThreshold = 3
    private static let diskThreshold = 0.8

    private var states: [String: ContainerState] = [:]
    private var restarts: [String: [Date]] = [:]
    private var loopAlertedAt: [String: Date] = [:]
    private var colimaWasRunning: Bool?
    /// How many containers the rules remember (for tests).
    var trackedContainers: Int { states.count }
    private var diskAlerted = false

    /// Call with every container list; the first sighting of a container never alerts.
    mutating func containersChanged(_ containers: [Container], now: Date) -> [Alert] {
        var alerts: [Alert] = []
        // Only the containers in this list matter next time; forget the ones that are gone.
        defer {
            let current = Set(containers.map(\.id))
            states = states.filter { current.contains($0.key) }
            restarts = restarts.filter { current.contains($0.key) }
            loopAlertedAt = loopAlertedAt.filter { current.contains($0.key) }
        }
        for container in containers {
            defer { states[container.id] = container.state }
            guard let previous = states[container.id], previous != container.state else { continue }

            if previous == .running, container.state == .exited, let code = Self.exitCode(container.status), code != 0 {
                alerts.append(Alert(
                    kind: .containerCrashed,
                    title: "\(container.name) exited with code \(code)",
                    body: "It stopped unexpectedly. Open ColiUI to read its logs.",
                    identifier: "crash-\(container.id)"
                ))
            }

            if container.state == .restarting {
                let recent = (restarts[container.id] ?? []).filter { now.timeIntervalSince($0) < Self.loopWindow } + [now]
                restarts[container.id] = recent
                let alertedRecently = loopAlertedAt[container.id].map { now.timeIntervalSince($0) < Self.loopWindow } ?? false
                if recent.count > Self.loopThreshold, !alertedRecently {
                    loopAlertedAt[container.id] = now
                    alerts.append(Alert(
                        kind: .restartLoop,
                        title: "\(container.name) is restarting in a loop",
                        body: "\(recent.count) restarts in the last 5 minutes.",
                        identifier: "loop-\(container.id)"
                    ))
                }
            }
        }
        return alerts
    }

    mutating func colimaChanged(isRunning: Bool, userStopped: Bool, profile: String) -> [Alert] {
        defer { colimaWasRunning = isRunning }
        guard colimaWasRunning == true, !isRunning, !userStopped else { return [] }
        return [Alert(
            kind: .colimaStopped,
            title: "Colima “\(profile)” stopped",
            body: "Docker isn't available until the VM starts again.",
            identifier: "colima-stopped"
        )]
    }

    static func colimaStartFailed(profile: String, message: String) -> Alert {
        Alert(kind: .colimaStopped, title: "Colima “\(profile)” failed to start", body: message, identifier: "colima-failed")
    }

    /// Alerts once when usage passes 80%, again only after it drops back below.
    mutating func diskMeasured(used: Int64, capacity: Int64, profile: String) -> [Alert] {
        guard capacity > 0 else { return [] }
        let fraction = Double(used) / Double(capacity)
        guard fraction > Self.diskThreshold else {
            diskAlerted = false
            return []
        }
        guard !diskAlerted else { return [] }
        diskAlerted = true
        return [Alert(
            kind: .diskAlmostFull,
            title: "Colima “\(profile)” disk is \(Int((fraction * 100).rounded()))% full",
            body: "Open Cleanup to free space.",
            identifier: Self.diskIdentifier
        )]
    }

    static func pullFinished(reference: String, duration: Duration) -> Alert? {
        guard duration > .seconds(10) else { return nil }
        return Alert(kind: .pullFinished, title: "Pulled \(reference)", body: "Took \(duration.components.seconds) s.",
                     identifier: "pull-\(reference)")
    }

    /// "Exited (137) 1 second ago" → 137.
    private static func exitCode(_ status: String) -> Int? {
        guard let open = status.firstIndex(of: "("), let close = status[open...].firstIndex(of: ")") else { return nil }
        return Int(status[status.index(after: open)..<close])
    }
}
