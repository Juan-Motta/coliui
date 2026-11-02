import Testing
@testable import ColiUI

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
