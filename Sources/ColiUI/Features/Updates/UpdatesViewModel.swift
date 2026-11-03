import ColiUICore
import Foundation
import Observation

/// What starts update checks: Sparkle in the app (SparkleUpdater), a fake in tests.
@MainActor
protocol AppUpdating: AnyObject {
    var automaticallyChecks: Bool { get set }
    var lastCheckDate: Date? { get }
    /// False when a check can't start now (one is already running in the background).
    func checkForUpdates() -> Bool
}

/// The answer to an offered or downloaded update.
enum UpdateChoice: Equatable {
    case install, skip, later
}

/// Settings › About › Updates, the update modal and the menu bar banner (Updates.dc.html).
/// The updater reports each stage through the `checkStarted` … `finished` calls; the UI answers through
/// `install`, `later`, `skip`, `cancelDownload` and `relaunch`.
@MainActor
@Observable
final class UpdatesViewModel {
    struct Offer: Equatable {
        let version: String
        let currentVersion: String
        let downloadBytes: UInt64
        let notes: [ReleaseNotes.Section]
    }

    enum Status: Equatable {
        case idle, checking, upToDate, available
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { true } else { false }
        }
    }

    enum Step: Equatable {
        case available
        case downloading(received: UInt64, expected: UInt64)
        case verifying, ready, installing
    }

    private(set) var status: Status = .idle
    private(set) var offer: Offer?
    private(set) var step: Step?
    private(set) var lastChecked: Date?
    /// The modal is open; closing it leaves a download going.
    private(set) var isModalOpen = false

    private let updater: AppUpdating?
    @ObservationIgnored private var reply: ((UpdateChoice) -> Void)?
    @ObservationIgnored private var cancel: (() -> Void)?
    @ObservationIgnored private var checkStartedAt: ContinuousClock.Instant?
    /// A local or cached feed answers in milliseconds; "Checking…" stays this long so the click shows.
    private let minimumChecking: Duration

    init(updater: AppUpdating?, minimumChecking: Duration = .milliseconds(700)) {
        self.updater = updater
        self.minimumChecking = minimumChecking
        lastChecked = updater?.lastCheckDate
    }

    /// False in builds without the Sparkle feed and key (`swift run`, ad-hoc bundles).
    var canUpdate: Bool { updater != nil }

    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecks ?? false }
        set { updater?.automaticallyChecks = newValue }
    }

    /// Banner in the menu bar and "View update" in About.
    var isUpdateWaiting: Bool { offer != nil }

    // MARK: Actions from the UI

    /// Where "Check for Updates…" in the menus takes you.
    enum MenuDestination: Equatable {
        /// An update already waits: its modal.
        case modal
        /// Settings › About, where the check's progress and result show.
        case about
    }

    /// "Check for Updates…" in the app menu and the menu bar: opens the waiting update, or checks with
    /// About on screen so the result is visible even when ColiUI is up to date.
    func checkFromMenu() -> MenuDestination {
        if offer != nil {
            isModalOpen = true
            return .modal
        }
        check()
        return .about
    }

    func check() {
        guard let updater, status != .checking else { return }
        let previous = status
        status = .checking
        checkStartedAt = .now
        if !updater.checkForUpdates() {
            status = previous
            checkStartedAt = nil
        }
    }

    func viewUpdate() {
        if offer != nil { isModalOpen = true }
    }

    func closeModal() {
        isModalOpen = false
    }

    func install() {
        answer(.install)
    }

    /// Not now; Sparkle asks again on a later check (or installs a downloaded update on quit).
    func later() {
        answer(.later)
        isModalOpen = false
    }

    func skip() {
        answer(.skip)
        isModalOpen = false
    }

    func relaunch() {
        answer(.install)
    }

    func cancelDownload() {
        cancel?()
        cancel = nil
    }

    // MARK: Reports from the updater

    func checkStarted(cancel: @escaping () -> Void) {
        status = .checking
        checkStartedAt = checkStartedAt ?? .now
        self.cancel = cancel
    }

    func found(_ offer: Offer, alreadyDownloaded: Bool, reply: @escaping (UpdateChoice) -> Void) {
        self.offer = offer
        self.reply = reply
        cancel = nil
        step = alreadyDownloaded ? .ready : .available
        status = .available
        checkStartedAt = nil
        lastChecked = updater?.lastCheckDate ?? lastChecked
    }

    func notFound() {
        cancel = nil
        let shown = checkStartedAt.map { ContinuousClock.now - $0 } ?? minimumChecking
        checkStartedAt = nil
        guard shown < minimumChecking else { return showUpToDate() }
        Task { [weak self, minimumChecking] in
            try? await Task.sleep(for: minimumChecking - shown)
            self?.showUpToDate()
        }
    }

    private func showUpToDate() {
        guard status == .checking else { return }
        status = .upToDate
        lastChecked = max(updater?.lastCheckDate ?? .distantPast, Date())
    }

    /// A failed check, download or install ends the session; the reason shows in About.
    func failed(_ message: String) {
        checkStartedAt = nil
        status = .failed(message)
        clearSession()
        lastChecked = updater?.lastCheckDate ?? lastChecked
    }

    func downloadStarted(cancel: @escaping () -> Void) {
        self.cancel = cancel
        step = .downloading(received: 0, expected: offer?.downloadBytes ?? 0)
    }

    func downloadExpects(_ bytes: UInt64) {
        guard case .downloading(let received, _) = step else { return }
        step = .downloading(received: received, expected: bytes)
    }

    func downloadReceived(_ bytes: UInt64) {
        guard case .downloading(let received, let expected) = step else { return }
        step = .downloading(received: received + bytes, expected: expected)
    }

    func verifying() {
        step = .verifying
        cancel = nil
    }

    func readyToRelaunch(reply: @escaping (UpdateChoice) -> Void) {
        self.reply = reply
        step = .ready
    }

    func installing() {
        step = .installing
    }

    /// Sparkle asks to bring the update forward (its window would come to the front).
    func focus() {
        if offer != nil { isModalOpen = true }
    }

    /// The update session ended: installed, skipped, put off or cancelled.
    func finished() {
        if status == .available { status = .idle }
        clearSession()
    }

    // MARK: Text

    var statusText: String {
        switch status {
        case .idle, .upToDate: "ColiUI is up to date"
        case .checking: "Checking…"
        case .available: "Version \(offer?.version ?? "") is available"
        case .failed(let message): "Couldn't check for updates: \(message)"
        }
    }

    /// "Last checked today at 10:52", "yesterday at 9:04" or "Oct 30 at 9:04".
    var lastCheckedText: String? {
        guard let lastChecked else { return nil }
        let calendar = Calendar.current
        let locale = Locale(identifier: "en_US")
        let time = lastChecked.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        let day = calendar.isDateInToday(lastChecked) ? "today"
            : calendar.isDateInYesterday(lastChecked) ? "yesterday"
            : lastChecked.formatted(Date.FormatStyle().month(.abbreviated).day().locale(locale))
        return "Last checked \(day) at \(time)"
    }

    var sizeText: String {
        Self.bytes(offer?.downloadBytes ?? 0)
    }

    /// 0…1 while downloading.
    var downloadProgress: Double {
        guard case .downloading(let received, let expected) = step, expected > 0 else { return 0 }
        return min(1, Double(received) / Double(expected))
    }

    var downloadText: String {
        guard case .downloading(let received, let expected) = step else { return "" }
        guard expected > 0 else { return Self.bytes(received) }
        return "\(Self.bytes(received)) of \(Self.bytes(expected)) · \(Int(downloadProgress * 100))%"
    }

    private func answer(_ choice: UpdateChoice) {
        let reply = reply
        self.reply = nil
        reply?(choice)
    }

    private func clearSession() {
        offer = nil
        step = nil
        reply = nil
        cancel = nil
        isModalOpen = false
    }

    /// English like the rest of the UI ("3.2 MB", never "3,2 MB").
    nonisolated static func bytes(_ count: UInt64) -> String {
        Int64(clamping: count).formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US")))
    }
}
