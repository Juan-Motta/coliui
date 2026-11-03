import ColiUICore
import Foundation
import Observation
import ServiceManagement

/// Registers ColiUI as a login item.
protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class MainAppLoginItem: LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum StatsInterval: String, CaseIterable, Identifiable {
    case twoSeconds = "2 seconds"
    case fiveSeconds = "5 seconds"
    case off = "Off"

    var id: Self { self }

    var duration: Duration? {
        switch self {
        case .twoSeconds: .seconds(2)
        case .fiveSeconds: .seconds(5)
        case .off: nil
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }
}

enum NotificationKind: String, CaseIterable, Identifiable {
    case containerCrashed, restartLoop, colimaStopped, diskAlmostFull, pullFinished

    var id: Self { self }

    var title: String {
        switch self {
        case .containerCrashed: "Container exited with an error"
        case .restartLoop: "Restart loop detected"
        case .colimaStopped: "Colima VM stopped or failed to start"
        case .diskAlmostFull: "VM disk almost full"
        case .pullFinished: "Image pull finished"
        }
    }

    var detail: String {
        switch self {
        case .containerCrashed: "When a container stops with a non-zero exit code"
        case .restartLoop: "More than 3 restarts within 5 minutes"
        case .colimaStopped: "Includes unexpected shutdowns"
        case .diskAlmostFull: "When usage passes 80% — links to Cleanup"
        case .pullFinished: "For pulls longer than 10 seconds"
        }
    }
}

/// Settings › General › Docker engine (Engines.dc.html).
enum EngineChoice: String, CaseIterable, Identifiable {
    case automatic, colima, dockerDesktop, orbStack, rancherDesktop, custom

    var id: Self { self }

    /// The engine a fixed choice means; nil for Automatic and Custom socket.
    var kind: DockerEngineKind? {
        switch self {
        case .colima: .colima
        case .dockerDesktop: .dockerDesktop
        case .orbStack: .orbStack
        case .rancherDesktop: .rancherDesktop
        case .automatic, .custom: nil
        }
    }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .custom: "Custom socket…"
        default: kind?.displayName ?? ""
        }
    }
}

/// Settings.dc.html preferences, stored in UserDefaults. Defaults follow the design.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let startColima = "startColimaOnOpen", showInDock = "showInDock", profile = "defaultProfile"
        static let socket = "socketPath", stats = "statsInterval", theme = "theme", notifications = "notifications"
        static let engine = "engine"
    }

    static let defaultNotifications: Set<NotificationKind> = [.containerCrashed, .restartLoop, .colimaStopped, .diskAlmostFull]

    var startColimaOnOpen: Bool { didSet { defaults.set(startColimaOnOpen, forKey: Key.startColima) } }
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: Key.showInDock) } }
    /// Applies the next time ColiUI opens.
    var defaultProfile: String { didSet { defaults.set(defaultProfile, forKey: Key.profile) } }
    /// Which Docker engine to talk to. Applies the next time ColiUI opens.
    var engine: EngineChoice { didSet { defaults.set(engine.rawValue, forKey: Key.engine) } }
    /// The socket for Engine › Custom socket. Applies the next time ColiUI opens.
    var socketPath: String { didSet { defaults.set(socketPath, forKey: Key.socket) } }
    var statsInterval: StatsInterval { didSet { defaults.set(statsInterval.rawValue, forKey: Key.stats) } }
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    private(set) var notifications: Set<NotificationKind> {
        didSet { defaults.set(notifications.map(\.rawValue).sorted(), forKey: Key.notifications) }
    }
    private(set) var loginItemError: String?
    /// The open Settings tab; not persisted.
    var tab: SettingsTab = .general

    private let defaults: UserDefaults
    private let loginItem: LoginItem

    init(defaults: UserDefaults = .standard, loginItem: LoginItem = MainAppLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        startColimaOnOpen = defaults.object(forKey: Key.startColima) as? Bool ?? true
        showInDock = defaults.object(forKey: Key.showInDock) as? Bool ?? false
        defaultProfile = defaults.string(forKey: Key.profile) ?? "default"
        let savedSocket = defaults.string(forKey: Key.socket) ?? ""
        socketPath = savedSocket
        // Before engines, a non-empty socket overrode detection; keep that for people who set one.
        engine = defaults.string(forKey: Key.engine).flatMap(EngineChoice.init)
            ?? (savedSocket.trimmingCharacters(in: .whitespaces).isEmpty ? .automatic : .custom)
        statsInterval = defaults.string(forKey: Key.stats).flatMap(StatsInterval.init) ?? .twoSeconds
        theme = defaults.string(forKey: Key.theme).flatMap(AppTheme.init) ?? .system
        notifications = (defaults.stringArray(forKey: Key.notifications)?.compactMap(NotificationKind.init))
            .map(Set.init) ?? Self.defaultNotifications
    }

    /// Read from the system each time: the user can also change it in System Settings › Login Items.
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return loginItem.isEnabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    try loginItem.setEnabled(newValue)
                    loginItemError = nil
                } catch {
                    loginItemError = "Couldn't change the login item: \(error.localizedDescription)"
                }
            }
        }
    }

    func isEnabled(_ kind: NotificationKind) -> Bool {
        notifications.contains(kind)
    }

    func setNotification(_ kind: NotificationKind, enabled: Bool) {
        if enabled { notifications.insert(kind) } else { notifications.remove(kind) }
    }

    /// The engine and socket this choice means; `answers` probes a socket (Automatic tries them in order).
    func resolvedEngine(environment: [String: String], home: String, answers: (String) -> Bool) -> DetectedEngine {
        switch engine {
        case .automatic:
            return EngineDetection.automatic(environment: environment, home: home, profile: defaultProfile, answers: answers)
        case .custom:
            let custom = socketPath.trimmingCharacters(in: .whitespaces)
            let path = custom.hasPrefix("~") ? home + custom.dropFirst() : custom
            return DetectedEngine(kind: .other, socketPath: path, isAnswering: answers(path))
        case .colima, .dockerDesktop, .orbStack, .rancherDesktop:
            let kind = engine.kind!
            let path = kind.socket(home: home, profile: defaultProfile)!
            return DetectedEngine(kind: kind, socketPath: path, isAnswering: answers(path))
        }
    }
}
