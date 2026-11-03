import ColiUICore
import Foundation
import Sparkle

/// Sparkle checks the appcast, downloads the update and verifies its EdDSA signature and Developer ID before
/// installing. ColiUI draws every screen: `SparkleUserDriver` forwards Sparkle's stages to UpdatesViewModel.
@MainActor
final class SparkleUpdater: AppUpdating {
    private let updater: SPUUpdater
    private let driver: SparkleUserDriver

    /// The view model driven by Sparkle (it keeps the updater alive); nil when this build has no feed or
    /// public key (`swift run`, ad-hoc bundles) or Sparkle won't start.
    static func makeViewModel(bundle: Bundle = .main) -> UpdatesViewModel? {
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty,
              bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return nil }
        let driver = SparkleUserDriver()
        let updater = SparkleUpdater(bundle: bundle, driver: driver)
        do {
            try updater.updater.start()
        } catch {
            return nil
        }
        let model = UpdatesViewModel(updater: updater)
        driver.model = model
        return model
    }

    private init(bundle: Bundle, driver: SparkleUserDriver) {
        self.driver = driver
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
    }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheckDate: Date? { updater.lastUpdateCheckDate }

    func checkForUpdates() -> Bool {
        guard updater.canCheckForUpdates else { return false }
        updater.checkForUpdates()
        return true
    }
}

/// Sparkle's UI callbacks, translated for UpdatesViewModel. No Sparkle window is ever shown.
@MainActor
final class SparkleUserDriver: NSObject, SPUUserDriver {
    weak var model: UpdatesViewModel?

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Settings › About has the switch; checking automatically is the default, so never ask.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        model?.checkStarted(cancel: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let offer = UpdatesViewModel.Offer(
            version: appcastItem.displayVersionString,
            currentVersion: current,
            downloadBytes: appcastItem.contentLength,
            notes: ReleaseNotes.parse(appcastItem.itemDescription ?? "")
        )
        model?.found(offer, alreadyDownloaded: state.stage != .notDownloaded) { reply(Self.sparkleChoice($0)) }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model?.notFound()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model?.failed(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        model?.downloadStarted(cancel: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        model?.downloadExpects(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        model?.downloadReceived(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        model?.verifying()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        model?.readyToRelaunch { reply(Self.sparkleChoice($0)) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        model?.installing()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        model?.finished()
        acknowledgement()
    }

    func showUpdateInFocus() {
        model?.focus()
    }

    func dismissUpdateInstallation() {
        model?.finished()
    }

    private static func sparkleChoice(_ choice: UpdateChoice) -> SPUUserUpdateChoice {
        switch choice {
        case .install: .install
        case .skip: .skip
        case .later: .dismiss
        }
    }
}
