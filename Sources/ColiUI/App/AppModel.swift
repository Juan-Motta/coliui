import AppKit
import ColiUICore
import Foundation
import Observation

/// Composition root: wires adapters into view models and keeps them fresh.
@MainActor
@Observable
final class AppModel {
    let containers: ContainersViewModel
    let colima: ColimaViewModel
    let cleanup: CleanupViewModel
    let profiles: ProfilesViewModel
    let images: ImagesViewModel
    let volumes: VolumesViewModel
    let networks: NetworksViewModel
    let settings: AppSettings
    let notifier: Notifying
    /// The socket this session talks to; Settings changes apply on the next launch.
    let socketPath: String
    var section: SidebarSection? = .containers
    /// Settings opens as a sheet over the main window.
    var isSettingsPresented = false
    private(set) var summary: DockerSummary?
    /// The open container detail, if any (shown in place of the list).
    private(set) var detail: ContainerDetailViewModel?
    /// The "Run a new container" sheet, while open.
    private(set) var runForm: RunContainerViewModel?

    private let repository: ContainerRepository?
    private let runner: ContainerRunner?
    private let logSource: ContainerLogSource?
    private let inventory: DockerInventory?
    private let events: (@Sendable () -> AsyncThrowingStream<Void, Error>)?
    private var pollTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var alertRules = AlertRules()

    static let shared = AppModel.live()

    init(
        containers: ContainersViewModel,
        colima: ColimaViewModel,
        cleanup: CleanupViewModel,
        profiles: ProfilesViewModel,
        images: ImagesViewModel,
        volumes: VolumesViewModel,
        networks: NetworksViewModel,
        settings: AppSettings,
        notifier: Notifying = SystemNotifier(),
        socketPath: String = "",
        repository: ContainerRepository? = nil,
        runner: ContainerRunner? = nil,
        logSource: ContainerLogSource? = nil,
        inventory: DockerInventory? = nil,
        events: (@Sendable () -> AsyncThrowingStream<Void, Error>)? = nil
    ) {
        self.containers = containers
        self.colima = colima
        self.cleanup = cleanup
        self.profiles = profiles
        self.images = images
        self.volumes = volumes
        self.networks = networks
        self.settings = settings
        self.notifier = notifier
        self.socketPath = socketPath
        self.repository = repository
        self.runner = runner
        self.logSource = logSource
        self.inventory = inventory
        self.events = events
        watchForAlerts()
    }

    func openDetail(_ container: Container, tab: DetailTab = .logs) {
        guard let repository, let logSource else { return }
        detail?.stop()
        // A stopped container's last lines are usually older than 15 minutes.
        let detail = ContainerDetailViewModel(
            containerID: container.id,
            repository: repository,
            logSource: logSource,
            range: container.isRunning ? .fifteenMinutes : .all,
            shellConnector: socketPath.isEmpty ? nil : DockerShell(socketPath: socketPath),
            inspector: repository as? ContainerInspector,
            environmentSource: repository as? ContainerEnvironmentSource,
            fileBrowser: repository as? ContainerFileBrowser
        )
        detail.tab = tab
        self.detail = detail
        Task { await detail.start() }
    }

    /// Opens the Run sheet; from the Images screen the image is filled in and already local, so no pull.
    func openRunForm(image: String? = nil) {
        guard let runner, runForm == nil else { return }
        let form = RunContainerViewModel(runner: runner)
        if let image {
            form.image = image
            form.pull = false
        }
        runForm = form
    }

    func closeRunForm() {
        runForm = nil
    }

    func submitRunForm() async {
        guard let form = runForm, let started = await form.run() else { return }
        runForm = nil
        await containers.refresh()
        if section == .images {
            images.showToast("Started \(started)")
        } else {
            containers.showToast("Started \(started)")
        }
    }

    func closeDetail() {
        detail?.stop()
        detail = nil
    }

    func select(_ section: SidebarSection) {
        closeDetail()
        self.section = section
        if section == .cleanup {
            Task { await cleanup.scan() }
        }
        if section == .profiles {
            Task { await profiles.load() }
        }
        if section == .images {
            Task { await images.refresh() }
        }
        if section == .volumes {
            Task { await volumes.refresh() }
        }
        if section == .networks {
            Task { await networks.refresh() }
        }
    }

    static func live(settings: AppSettings = AppSettings()) -> AppModel {
        let profile = settings.defaultProfile
        let socketPath = settings.resolvedSocket(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
        let repository = DockerEngineRepository(transport: UnixSocketTransport(socketPath: socketPath))
        let containers = ContainersViewModel(repository: repository)
        let runtime: ColimaRuntime = ColimaCLIRuntime.locateExecutable()
            .map { ColimaCLIRuntime(runner: ProcessCommandRunner(), executable: $0) }
            ?? UnavailableColimaRuntime()
        return AppModel(
            containers: containers,
            colima: ColimaViewModel(runtime: runtime, profile: profile),
            cleanup: CleanupViewModel(maintenance: repository),
            profiles: ProfilesViewModel(runtime: runtime, activeProfile: profile),
            images: ImagesViewModel(
                repository: repository,
                puller: DockerImagePuller(socketPath: socketPath),
                containers: { containers.containers }
            ),
            volumes: VolumesViewModel(repository: repository, containers: { containers.containers }),
            networks: NetworksViewModel(repository: repository, containers: { containers.containers }),
            settings: settings,
            socketPath: socketPath,
            repository: repository,
            runner: repository,
            logSource: DockerLogStream(socketPath: socketPath),
            inventory: repository,
            events: { DockerEvents.containerEvents(socketPath: socketPath) }
        )
    }

    /// Refreshes the list as soon as Docker reports a container event; reconnects after 5 s if the stream drops.
    private func startEvents() {
        guard eventsTask == nil, let events else { return }
        eventsTask = Task {
            while !Task.isCancelled {
                do {
                    for try await _ in events() { await containers.refresh() }
                } catch {}
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Polls containers every 3 s; Colima and sidebar totals every 15 s (each `colima list` spawns processes).
    /// Replace with the Docker events stream later.
    func startPolling() {
        startEvents()
        startStats()
        guard pollTask == nil else { return }
        // `docker system df` takes about a second, so measure once at launch and on demand.
        Task { await cleanup.scan() }
        pollTask = Task {
            var tick = 0
            while !Task.isCancelled {
                if tick % 5 == 0 {
                    await colima.refresh()
                    if tick == 0, settings.startColimaOnOpen { await colima.startIfStopped() }
                    summary = try? await inventory?.summary()
                    if section == .images { await images.refresh() }
                    if section == .volumes { await volumes.refresh() }
                    if section == .networks { await networks.refresh() }
                }
                // Re-measure the disk every ~5 minutes while its alert is on (`docker system df` takes about a second).
                if tick > 0, tick % 100 == 0, settings.isEnabled(.diskAlmostFull) {
                    await cleanup.scan()
                }
                await containers.refresh()
                tick += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Settings › Notifications: feeds what the view models observe into the alert rules.
    private func watchForAlerts() {
        containers.onRefresh = { [weak self] list in
            guard let self else { return }
            deliver(alertRules.containersChanged(list, now: Date()))
        }
        colima.onRefresh = { [weak self] colima in
            guard let self, colima.instance != nil else { return }
            deliver(alertRules.colimaChanged(isRunning: colima.isRunning, userStopped: colima.stoppedByUser, profile: colima.profile))
        }
        colima.onStartFailed = { [weak self] message in
            guard let self else { return }
            deliver([AlertRules.colimaStartFailed(profile: colima.profile, message: message)])
        }
        cleanup.onScan = { [weak self] usage in
            guard let self, let capacity = colima.instance?.diskBytes else { return }
            deliver(alertRules.diskMeasured(used: usage.totalBytes, capacity: capacity, profile: colima.profile))
        }
        images.onPullFinished = { [weak self] reference, duration in
            guard let self, let alert = AlertRules.pullFinished(reference: reference, duration: duration) else { return }
            deliver([alert])
        }
        notifier.onOpen = { [weak self] identifier in
            guard let self else { return }
            NSApp.activate()
            if identifier == AlertRules.diskIdentifier { select(.cleanup) }
        }
    }

    private func deliver(_ alerts: [Alert]) {
        for alert in alerts where settings.isEnabled(alert.kind) {
            notifier.post(title: alert.title, body: alert.body, identifier: alert.identifier)
        }
    }

    /// Settings › Refresh stats every: each stats round takes about a second, so the interval runs between rounds.
    private func startStats() {
        guard statsTask == nil else { return }
        statsTask = Task {
            while !Task.isCancelled {
                if let interval = settings.statsInterval.duration {
                    await containers.refreshStats()
                    try? await Task.sleep(for: interval)
                } else {
                    containers.clearStats()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    /// Whether the main window is on screen; it brings the Dock icon with it.
    private(set) var isMainWindowOpen = false

    func mainWindowOpened() {
        isMainWindowOpen = true
        applySystemSettings()
    }

    /// Closing the window keeps the app in the menu bar; only Quit ends it.
    func mainWindowClosed() {
        isMainWindowOpen = false
        applySystemSettings()
    }

    /// The Dock icon shows while the window is open; Settings › Show icon in Dock keeps it when it's closed.
    nonisolated static func showsDockIcon(showInDock: Bool, isMainWindowOpen: Bool) -> Bool {
        showInDock || isMainWindowOpen
    }

    /// Dock icon (Settings › Show icon in Dock plus the window) and Theme.
    func applySystemSettings() {
        let policy: NSApplication.ActivationPolicy =
            Self.showsDockIcon(showInDock: settings.showInDock, isMainWindowOpen: isMainWindowOpen) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // Becoming a regular app doesn't bring the window forward by itself.
            if policy == .regular { NSApp.activate() }
        }
        NSApp.appearance = switch settings.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func performColima(_ action: ColimaAction) async {
        await colima.perform(action)
        await containers.refresh()
    }
}

private struct UnavailableColimaRuntime: ColimaRuntime {
    func instances() async throws -> [ColimaInstance] { throw ColimaError.notInstalled }
    func start(profile: String) async throws { throw ColimaError.notInstalled }
    func stop(profile: String) async throws { throw ColimaError.notInstalled }
    func restart(profile: String) async throws { throw ColimaError.notInstalled }
    func settings(profile: String) async throws -> ColimaProfileSettings { throw ColimaError.notInstalled }
    func apply(_ settings: ColimaProfileSettings, to profile: String, isRunning: Bool) async throws { throw ColimaError.notInstalled }
    func create(profile: String, settings: ColimaProfileSettings) async throws { throw ColimaError.notInstalled }
    func delete(profile: String) async throws { throw ColimaError.notInstalled }
}
