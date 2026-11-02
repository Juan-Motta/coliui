import Testing
@testable import ColiUI

@Suite struct StatsSamplingTests {
    /// Each round asks Docker for every running container's stats (about a second each);
    /// only the containers list shows them, so nothing is sampled otherwise.
    @Test func samplesOnlyWhileTheListShowsThem() {
        #expect(AppModel.samplesStats(enabled: true, isMainWindowOpen: true, showsStatsColumns: true))
        #expect(!AppModel.samplesStats(enabled: true, isMainWindowOpen: false, showsStatsColumns: true))
        #expect(!AppModel.samplesStats(enabled: true, isMainWindowOpen: true, showsStatsColumns: false))
        #expect(!AppModel.samplesStats(enabled: false, isMainWindowOpen: true, showsStatsColumns: true))
    }
}

@Suite struct DockIconTests {
    /// The window brings the Dock icon; with it closed only the menu bar icon stays,
    /// unless Settings › Show icon in Dock keeps it there all the time.
    @Test func dockIconFollowsTheWindow() {
        #expect(AppModel.showsDockIcon(showInDock: false, isMainWindowOpen: true))
        #expect(!AppModel.showsDockIcon(showInDock: false, isMainWindowOpen: false))
        #expect(AppModel.showsDockIcon(showInDock: true, isMainWindowOpen: true))
        #expect(AppModel.showsDockIcon(showInDock: true, isMainWindowOpen: false))
    }
}
