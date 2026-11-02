import ColiUICore
import Foundation
import Observation

enum DetailTab: String, CaseIterable, Identifiable {
    case logs = "Logs"
    case stats = "Stats"
    case terminal = "Terminal"
    case files = "Files"
    case inspect = "Inspect"
    case environment = "Environment"

    var id: Self { self }
}

enum LogRange: String, CaseIterable, Identifiable {
    case fifteenMinutes = "15 min"
    case hour = "1 hour"
    case all = "All"

    var id: Self { self }

    func since(_ now: Date) -> Date? {
        switch self {
        case .fifteenMinutes: now.addingTimeInterval(-15 * 60)
        case .hour: now.addingTimeInterval(-60 * 60)
        case .all: nil
        }
    }
}

@MainActor
@Observable
final class ContainerDetailViewModel {
    static let maxLines = 5000

    let containerID: String
    private(set) var details: ContainerDetails?
    private(set) var lines: [LogLine] = []
    private(set) var range: LogRange = .fifteenMinutes
    private(set) var streamError: String?
    var tab: DetailTab = .logs
    var filterText = ""
    var useRegex = false
    var follow = true
    var showTimestamps = true
    /// The Stats tab; samples only while that tab is open.
    let liveStats: LiveStatsViewModel
    /// The Terminal tab; nil when no shell connector is available.
    let terminal: TerminalViewModel?
    /// The Inspect tab; nil when the repository can't inspect.
    let inspect: InspectViewModel?
    /// The Environment tab; nil when the repository can't read the environment.
    let environment: EnvironmentViewModel?
    /// The Files tab; nil when the repository can't browse files.
    let files: FilesViewModel?

    private let repository: ContainerRepository
    private let logSource: ContainerLogSource
    private let now: () -> Date
    private var streamTask: Task<Void, Never>?
    private var isStopped = false
    /// Lines waiting for the next flush; a whole history arrives in a few updates instead of one per line,
    /// so the panel opens at the newest line instead of visibly scrolling through the backlog.
    private var pending: [LogLine] = []
    private var flushScheduled = false
    static let flushInterval: Duration = .milliseconds(50)

    init(
        containerID: String,
        repository: ContainerRepository,
        logSource: ContainerLogSource,
        range: LogRange = .fifteenMinutes,
        shellConnector: ShellConnector? = nil,
        inspector: ContainerInspector? = nil,
        environmentSource: ContainerEnvironmentSource? = nil,
        fileBrowser: ContainerFileBrowser? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.containerID = containerID
        self.repository = repository
        self.logSource = logSource
        self.range = range
        self.now = now
        liveStats = LiveStatsViewModel(containerID: containerID, repository: repository)
        terminal = shellConnector.map { TerminalViewModel(containerID: containerID, connector: $0) }
        inspect = inspector.map { InspectViewModel(containerID: containerID, inspector: $0) }
        environment = environmentSource.map { EnvironmentViewModel(containerID: containerID, source: $0) }
        files = fileBrowser.map { FilesViewModel(containerID: containerID, browser: $0) }
    }

    private var regex: Regex<AnyRegexOutput>? {
        guard useRegex, !filterText.isEmpty else { return nil }
        return try? Regex(filterText).ignoresCase()
    }

    var isRegexValid: Bool { !useRegex || filterText.isEmpty || regex != nil }

    var visibleLines: [LogLine] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return lines }
        if useRegex {
            guard let regex else { return [] }
            return lines.filter { $0.message.contains(regex) }
        }
        return lines.filter { $0.message.localizedCaseInsensitiveContains(query) }
    }

    func start() async {
        details = try? await repository.details(id: containerID)
        // Closed while the details were loading: a stream started now would never be stopped.
        guard !isStopped else { return }
        startLogs()
    }

    /// Files › Shell here: the Terminal tab, `cd` into `folder`.
    func openShell(in folder: String) {
        tab = .terminal
        terminal?.run("cd -- " + TerminalViewModel.shellQuoted(folder))
    }

    func stop() {
        isStopped = true
        streamTask?.cancel()
        streamTask = nil
        terminal?.disconnect()
    }

    func select(range: LogRange) {
        guard range != self.range else { return }
        self.range = range
        startLogs()
    }

    func clear() {
        lines = []
        pending = []
    }

    /// Visible lines as "2026-11-01T10:42:01Z INFO message".
    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return visibleLines.map { line in
            [line.timestamp.map(formatter.string(from:)), line.level.map { $0.rawValue.uppercased() }, line.message]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    /// Lets tests wait until a finite stream has been consumed.
    func waitForLogs() async {
        await streamTask?.value
    }

    private func startLogs() {
        streamTask?.cancel()
        lines = []
        pending = []
        streamError = nil
        let stream = logSource.logs(
            id: containerID,
            since: range.since(now()),
            tail: Self.maxLines,
            tty: details?.tty ?? false
        )
        streamTask = Task { [weak self] in
            do {
                for try await line in stream {
                    self?.append(line)
                }
                self?.flush()
            } catch {
                guard !Task.isCancelled else { return }
                self?.flush()
                self?.streamError = error.localizedDescription
            }
        }
    }

    private func append(_ line: LogLine) {
        pending.append(line)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        lines.append(contentsOf: pending)
        pending = []
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }
}
