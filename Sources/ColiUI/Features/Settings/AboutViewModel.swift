import ColiUICore
import Foundation
import Observation

/// Settings › About: the app's version and what it runs against, plus a copy-ready diagnostics block.
@MainActor
@Observable
final class AboutViewModel {
    struct Row: Equatable {
        let title: String
        let value: String
    }

    static let repository = URL(string: "https://github.com/Juan-Motta/coliui")!
    static let newIssue = URL(string: "https://github.com/Juan-Motta/coliui/issues/new")!

    let appVersion: String
    private(set) var rows: [Row] = []
    /// "Copy diagnostics" reads "Copied" for two seconds.
    private(set) var justCopied = false
    @ObservationIgnored private var copiedReset: Task<Void, Never>?

    private let colima: ColimaVersionSource?
    private let engine: EngineVersionSource?
    private let socketPath: String
    private let home: String
    private let system: String

    init(colima: ColimaVersionSource?, engine: EngineVersionSource?, socketPath: String,
         home: String = NSHomeDirectory(), appVersion: String = AboutViewModel.bundleVersion,
         system: String = AboutViewModel.systemDescription) {
        self.colima = colima
        self.engine = engine
        self.socketPath = socketPath
        self.home = home
        self.appVersion = appVersion
        self.system = system
    }

    func load(profile: String, vmType: String?) async {
        let colimaVersion = try? await colima?.version()
        let engineVersion = try? await engine?.engineVersion()
        let socket = socketPath.hasPrefix(home + "/") ? "~" + socketPath.dropFirst(home.count) : socketPath
        rows = [
            Row(title: "Colima", value: colimaVersion.map { "\($0) · profile \(profile)" + (vmType.map { " (\($0))" } ?? "") } ?? "Not installed"),
            Row(title: "Docker Engine", value: engineVersion.map { "\($0.version) · API \($0.apiVersion)" } ?? "Not reachable"),
            Row(title: "macOS", value: system),
            Row(title: "Docker socket", value: socket),
        ]
    }

    func markCopied() {
        justCopied = true
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }

    /// What "Copy diagnostics" puts on the clipboard, ready to paste into an issue.
    var diagnostics: String {
        (["ColiUI \(appVersion)"] + rows.map { "\($0.title): \($0.value)" }).joined(separator: "\n")
    }

    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        return info?["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
    }

    static var systemDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var machine = utsname()
        uname(&machine)
        let arch = withUnsafeBytes(of: &machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let chip = arch == "arm64" ? "Apple silicon" : "Intel"
        return "\(version.majorVersion).\(version.minorVersion) · \(chip)"
    }
}
