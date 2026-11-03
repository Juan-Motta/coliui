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
    /// Settings › About; nil in tests that don't need it.
    let about: AboutViewModel?
    let cleanup: CleanupViewModel
    let profiles: ProfilesViewModel
    let images: ImagesViewModel
    let volumes: VolumesViewModel
    let networks: NetworksViewModel
    /// Settings › About › Updates, the update modal and the menu bar banner.
    let updates: UpdatesViewModel
    let settings: AppSettings
    let notifier: Notifying
    /// The socket this session talks to; Settings changes apply on the next launch.
    let socketPath: String
    /// The engine chosen when ColiUI opened (Settings › Docker engine).
    let engine: DetectedEngine
    /// What the engine says about itself; nil until it answers, or while it doesn't.
    private(set) var engineInfo: EngineInfo?
    /// The Engine setting this session started with, to tell when a change waits for a relaunch.
    let launchedEngineChoice: EngineChoice
    private let colimaInstalled: Bool
    private let engineInfoSource: EngineInfoSource?
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
        about: AboutViewModel? = nil,
        updates: UpdatesViewModel = UpdatesViewModel(updater: nil),
        notifier: Notifying = SystemNotifier(),
        socketPath: String = "",
        engine: DetectedEngine = DetectedEngine(kind: .colima, socketPath: "", isAnswering: true),
        colimaInstalled: Bool = true,
        engineInfoSource: EngineInfoSource? = nil,
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
        self.about = about
        self.updates = updates
        self.notifier = notifier
        self.socketPath = socketPath
        self.engine = engine
        self.colimaInstalled = colimaInstalled
        self.engineInfoSource = engineInfoSource
        launchedEngineChoice = settings.engine
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

    /// The create modal on screen, if any (Settings has its own).
    enum PresentedModal {
        case run(RunContainerViewModel), pullImage, newVolume, newNetwork, newProfile, update

        /// Run container and New profile are long forms and sit near the top; the rest lower down.
        var isTall: Bool {
            switch self {
            case .run, .newProfile: true
            case .pullImage, .newVolume, .newNetwork, .update: false
            }
        }
    }

    var presentedModal: PresentedModal? {
        if let runForm { return .run(runForm) }
        if images.isPullOpen { return .pullImage }
        if volumes.isCreateOpen { return .newVolume }
        if networks.isCreateOpen { return .newNetwork }
        if profiles.isCreating { return .newProfile }
        if updates.isModalOpen { return .update }
        return nil
    }

    /// A click outside the modal. Closing Pull image leaves a running pull going.
    func dismissModal() {
        switch presentedModal {
        case .run: closeRunForm()
        case .pullImage: images.closePull()
        case .newVolume: volumes.closeCreate()
        case .newNetwork: networks.closeCreate()
        case .newProfile: profiles.cancelNewProfile()
        case .update: updates.closeModal()
        case nil: break
        }
    }

    /// "View update" in About and the menu bar banner: the modal draws under Settings, so Settings closes first.
    func viewUpdate() {
        isSettingsPresented = false
        updates.viewUpdate()
    }

    /// "Check for Updates…" in the app menu and the menu bar (the menu bar also brings the window forward).
    func checkForUpdatesFromMenu() {
        switch updates.checkFromMenu() {
        case .modal:
            isSettingsPresented = false
        case .about:
            settings.tab = .about
            isSettingsPresented = true
        }
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
        let engine = settings.resolvedEngine(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(),
                                             answers: UnixSocketTransport.answers)
        let socketPath = engine.socketPath
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
            about: AboutViewModel(colima: runtime as? ColimaVersionSource, engine: repository, socketPath: socketPath),
            updates: SparkleUpdater.makeViewModel() ?? UpdatesViewModel(updater: nil),
            socketPath: socketPath,
            engine: engine,
            colimaInstalled: !(runtime is UnavailableColimaRuntime),
            engineInfoSource: repository,
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
                    // First: `/info` names an engine reached through another socket before the Colima check below.
                    engineInfo = try? await engineInfoSource?.engineInfo()
                    // Colima's controls only apply to Colima; `colima list` spawns processes, so skip it otherwise.
                    if usesColima {
                        await colima.refresh()
                        if tick == 0, settings.startColimaOnOpen { await colima.startIfStopped() }
                    }
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
        images.onRemoved = { [weak self] in
            guard let self else { return }
            Task { await cleanup.scan() }
        }
        cleanup.onCleaned = { [weak self] in
            guard let self else { return }
            Task {
                await images.refresh()
                await volumes.refresh()
                await networks.refresh()
            }
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
    /// Rounds run only while the containers list (the only screen with CPU / memory columns) is on screen.
    private func startStats() {
        guard statsTask == nil else { return }
        statsTask = Task {
            while !Task.isCancelled {
                let interval = settings.statsInterval.duration
                if interval == nil { containers.clearStats() }
                let sampling = Self.samplesStats(enabled: interval != nil, isMainWindowOpen: isMainWindowOpen,
                                                 showsStatsColumns: showsStatsColumns)
                if sampling, let interval {
                    await containers.refreshStats()
                    try? await Task.sleep(for: interval)
                } else {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    /// The containers list in its list layout, with no detail open.
    private var showsStatsColumns: Bool {
        (section ?? .containers) == .containers && detail == nil && containers.viewMode == .list
    }

    nonisolated static func samplesStats(enabled: Bool, isMainWindowOpen: Bool, showsStatsColumns: Bool) -> Bool {
        enabled && isMainWindowOpen && showsStatsColumns
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

    /// The engine in use: a custom socket or DOCKER_HOST is named from `/info` once the engine answers.
    var engineKind: DockerEngineKind {
        guard engine.kind == .other, let engineInfo else { return engine.kind }
        return DockerEngineKind.identify(engineInfo)
    }

    /// Colima's VM controls, Profiles and "Start Colima when ColiUI opens" (Engines.dc.html).
    var usesColima: Bool {
        engineKind == .colima && colimaInstalled
    }

    /// Whether the engine answers; with Colima the VM status says it instead.
    var isEngineRunning: Bool {
        usesColima ? colima.isRunning : engineInfo != nil || (engineInfoSource == nil && engine.isAnswering)
    }

    /// The installed app that manages a non-Colima engine ("Open OrbStack").
    var engineApp: URL? {
        engineKind.appBundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    func openEngineApp() {
        guard let engineApp else { return }
        NSWorkspace.shared.openApplication(at: engineApp, configuration: NSWorkspace.OpenConfiguration())
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
