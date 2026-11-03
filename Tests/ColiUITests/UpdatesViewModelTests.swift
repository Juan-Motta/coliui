import ColiUICore
import Foundation
import Testing
@testable import ColiUI

@MainActor
private final class FakeUpdater: AppUpdating {
    var automaticallyChecks = true
    var lastCheckDate: Date?
    var canCheck = true
    private(set) var checks = 0

    func checkForUpdates() -> Bool {
        guard canCheck else { return false }
        checks += 1
        return true
    }
}

@MainActor
private final class Replies {
    private(set) var choices: [UpdateChoice] = []
    private(set) var cancels = 0
    func reply(_ choice: UpdateChoice) { choices.append(choice) }
    func cancel() { cancels += 1 }
}

private let offer = UpdatesViewModel.Offer(
    version: "0.1.4", currentVersion: "0.1.3", downloadBytes: 3_200_000,
    notes: [.init(title: "Features", items: [.init(scope: "app", text: "check for updates")])]
)

@MainActor
@Suite struct UpdatesViewModelTests {
    @Test func aCheckShowsCheckingThenUpToDate() {
        let updater = FakeUpdater()
        let updates = UpdatesViewModel(updater: updater, minimumChecking: .zero)
        #expect(updates.statusText == "ColiUI is up to date")

        updates.check()
        #expect(updater.checks == 1)
        // The click shows at once, before Sparkle reports the check.
        #expect(updates.statusText == "Checking…")
        updates.checkStarted {}
        // A second click while checking starts nothing.
        updates.check()
        #expect(updater.checks == 1)

        updater.lastCheckDate = Date(timeIntervalSinceNow: -5)
        updates.notFound()
        #expect(updates.status == .upToDate)
        #expect(updates.lastChecked.map { abs($0.timeIntervalSinceNow) < 2 } == true)
        #expect(updates.lastCheckedText?.hasPrefix("Last checked today at ") == true)
        #expect(!updates.isUpdateWaiting)
    }

    @Test func aFastAnswerKeepsCheckingOnScreenForAMoment() async throws {
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .milliseconds(150))
        updates.check()
        updates.notFound()
        #expect(updates.status == .checking)
        let deadline = ContinuousClock.now + .seconds(2)
        while updates.status == .checking, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(updates.status == .upToDate)
    }

    @Test func aFoundUpdateWaitsInAboutUntilViewed() {
        let replies = Replies()
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .zero)
        updates.check()
        updates.found(offer, alreadyDownloaded: false, reply: replies.reply)

        #expect(updates.statusText == "Version 0.1.4 is available")
        #expect(updates.isUpdateWaiting)
        #expect(updates.step == .available)
        #expect(updates.sizeText == "3.2 MB")
        #expect(!updates.isModalOpen)

        updates.viewUpdate()
        #expect(updates.isModalOpen)
        #expect(replies.choices.isEmpty)
    }

    @Test func theMenusCheckWithAboutOnScreenOrOpenAWaitingUpdate() {
        let updater = FakeUpdater()
        let updates = UpdatesViewModel(updater: updater, minimumChecking: .zero)
        #expect(updates.checkFromMenu() == .about)
        #expect(updater.checks == 1)
        #expect(updates.status == .checking)
        updates.found(offer, alreadyDownloaded: false) { _ in }
        // Found from About: it waits there until viewed.
        #expect(!updates.isModalOpen)

        // With an update already waiting, the menus open it instead of checking again.
        #expect(updates.checkFromMenu() == .modal)
        #expect(updates.isModalOpen)
        #expect(updater.checks == 1)
    }

    @Test func installDownloadsThenAsksToRelaunch() {
        let replies = Replies()
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .zero)
        updates.found(offer, alreadyDownloaded: false, reply: replies.reply)
        updates.viewUpdate()

        updates.install()
        #expect(replies.choices == [.install])
        updates.downloadStarted(cancel: replies.cancel)
        updates.downloadExpects(3_200_000)
        updates.downloadReceived(1_000_000)
        updates.downloadReceived(400_000)
        #expect(updates.step == .downloading(received: 1_400_000, expected: 3_200_000))
        #expect(updates.downloadText == "1.4 MB of 3.2 MB · 43%")

        // Closing the modal leaves the download going.
        updates.closeModal()
        #expect(updates.step == .downloading(received: 1_400_000, expected: 3_200_000))
        #expect(replies.cancels == 0)

        updates.verifying()
        updates.readyToRelaunch(reply: replies.reply)
        #expect(updates.step == .ready)
        updates.relaunch()
        #expect(replies.choices == [.install, .install])
        updates.installing()
        #expect(updates.step == .installing)
    }

    @Test func cancelStopsTheDownload() {
        let replies = Replies()
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .zero)
        updates.found(offer, alreadyDownloaded: false, reply: replies.reply)
        updates.install()
        updates.downloadStarted(cancel: replies.cancel)
        updates.cancelDownload()
        updates.cancelDownload()
        #expect(replies.cancels == 1)
        updates.finished()
        #expect(updates.offer == nil)
        #expect(updates.step == nil)
        #expect(updates.status == .idle)
    }

    @Test func laterAndSkipAnswerOnceAndClose() {
        let replies = Replies()
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .zero)
        updates.found(offer, alreadyDownloaded: false, reply: replies.reply)
        updates.viewUpdate()
        updates.later()
        updates.later()
        #expect(replies.choices == [.later])
        #expect(!updates.isModalOpen)

        let skips = Replies()
        updates.found(offer, alreadyDownloaded: false, reply: skips.reply)
        updates.skip()
        #expect(skips.choices == [.skip])
    }

    @Test func aDownloadedUpdateOpensReadyToRelaunch() {
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .zero)
        updates.found(offer, alreadyDownloaded: true) { _ in }
        #expect(updates.step == .ready)
    }

    @Test func failuresShowInAboutAndEndTheSession() {
        let updates = UpdatesViewModel(updater: FakeUpdater(), minimumChecking: .zero)
        updates.found(offer, alreadyDownloaded: false) { _ in }
        updates.viewUpdate()
        updates.failed("The update is improperly signed.")
        #expect(updates.statusText == "Couldn't check for updates: The update is improperly signed.")
        #expect(!updates.isModalOpen)
        #expect(!updates.isUpdateWaiting)
    }

    @Test func aCheckThatCannotStartLeavesTheStatusAlone() {
        let updater = FakeUpdater()
        updater.canCheck = false
        let updates = UpdatesViewModel(updater: updater, minimumChecking: .zero)
        updates.check()
        #expect(updates.status == .idle)
    }

    @Test func theSwitchWritesThroughToTheUpdater() {
        let updater = FakeUpdater()
        let updates = UpdatesViewModel(updater: updater, minimumChecking: .zero)
        updates.automaticallyChecks = false
        #expect(!updater.automaticallyChecks)
    }

    @Test func withoutAnUpdaterNothingHappens() {
        let updates = UpdatesViewModel(updater: nil)
        #expect(!updates.canUpdate)
        updates.check()
        #expect(updates.status == .idle)
        #expect(!updates.automaticallyChecks)
    }
}
