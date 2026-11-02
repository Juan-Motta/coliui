import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeLoginItem: LoginItem, @unchecked Sendable {
    var isEnabled: Bool
    var error: Error?
    private(set) var calls: [Bool] = []

    init(isEnabled: Bool) { self.isEnabled = isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if let error { throw error }
        isEnabled = enabled
    }
}

private func freshDefaults() -> UserDefaults {
    let name = "coliui.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite struct AppSettingsTests {
    @Test func defaultsMatchTheDesign() {
        let settings = AppSettings(defaults: freshDefaults(), loginItem: FakeLoginItem(isEnabled: false))
        #expect(settings.startColimaOnOpen)
        #expect(!settings.showInDock)
        #expect(settings.defaultProfile == "default")
        #expect(settings.socketPath == "")
        #expect(settings.statsInterval == .twoSeconds)
        #expect(settings.theme == .system)
        #expect(settings.notifications == [.containerCrashed, .restartLoop, .colimaStopped, .diskAlmostFull])
        #expect(!settings.launchAtLogin)
    }

    @Test func persistsChanges() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, loginItem: FakeLoginItem(isEnabled: false))
        settings.startColimaOnOpen = false
        settings.showInDock = true
        settings.defaultProfile = "work"
        settings.socketPath = "~/custom.sock"
        settings.statsInterval = .off
        settings.theme = .dark
        settings.setNotification(.pullFinished, enabled: true)
        settings.setNotification(.restartLoop, enabled: false)

        let reloaded = AppSettings(defaults: defaults, loginItem: FakeLoginItem(isEnabled: false))
        #expect(!reloaded.startColimaOnOpen)
        #expect(reloaded.showInDock)
        #expect(reloaded.defaultProfile == "work")
        #expect(reloaded.socketPath == "~/custom.sock")
        #expect(reloaded.statsInterval == .off)
        #expect(reloaded.theme == .dark)
        #expect(reloaded.notifications == [.containerCrashed, .colimaStopped, .diskAlmostFull, .pullFinished])
    }

    @Test func launchAtLoginGoesThroughTheLoginItem() {
        let item = FakeLoginItem(isEnabled: false)
        let settings = AppSettings(defaults: freshDefaults(), loginItem: item)
        settings.launchAtLogin = true
        #expect(item.calls == [true])
        #expect(settings.launchAtLogin)
        #expect(settings.loginItemError == nil)
    }

    @Test func launchAtLoginFailureRevertsAndExplains() {
        let item = FakeLoginItem(isEnabled: false)
        item.error = CocoaError(.featureUnsupported)
        let settings = AppSettings(defaults: freshDefaults(), loginItem: item)
        settings.launchAtLogin = true
        #expect(!settings.launchAtLogin)
        #expect(settings.loginItemError != nil)
    }

    @Test func socketOverrideWinsAndExpandsTheHomeFolder() {
        let settings = AppSettings(defaults: freshDefaults(), loginItem: FakeLoginItem(isEnabled: false))
        settings.defaultProfile = "work"
        #expect(settings.resolvedSocket(environment: [:], home: "/Users/me") == "/Users/me/.colima/work/docker.sock")
        settings.socketPath = "  ~/run/docker.sock "
        #expect(settings.resolvedSocket(environment: [:], home: "/Users/me") == "/Users/me/run/docker.sock")
    }

    @Test func statsIntervals() {
        #expect(StatsInterval.twoSeconds.duration == .seconds(2))
        #expect(StatsInterval.fiveSeconds.duration == .seconds(5))
        #expect(StatsInterval.off.duration == nil)
    }
}

@MainActor
@Suite struct StartColimaOnOpenTests {
    private static func instance(_ name: String, _ status: ColimaStatus) -> ColimaInstance {
        ColimaInstance(name: name, status: status, arch: "aarch64", cpus: 2, memoryBytes: 2 << 30, diskBytes: 60 << 30, runtime: "docker")
    }

    @Test func startsTheProfileWhenStopped() async {
        let runtime = FakeColimaRuntime([Self.instance("default", .stopped)])
        let model = ColimaViewModel(runtime: runtime, profile: "default")
        await model.refresh()
        await model.startIfStopped()
        #expect(runtime.commands == ["start default"])
    }

    @Test func leavesARunningProfileAlone() async {
        let runtime = FakeColimaRuntime([Self.instance("default", .running)])
        let model = ColimaViewModel(runtime: runtime, profile: "default")
        await model.refresh()
        await model.startIfStopped()
        #expect(runtime.commands.isEmpty)
    }

    /// `colima start` would create a brand-new VM for a missing profile.
    @Test func neverCreatesAMissingProfile() async {
        let runtime = FakeColimaRuntime([Self.instance("work", .stopped)])
        let model = ColimaViewModel(runtime: runtime, profile: "default")
        await model.refresh()
        await model.startIfStopped()
        #expect(runtime.commands.isEmpty)
    }
}
