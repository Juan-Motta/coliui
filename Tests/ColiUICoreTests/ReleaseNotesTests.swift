import Testing
@testable import ColiUICore

@Suite struct ReleaseNotesTests {
    @Test func readsTheSectionsScriptsReleaseNotesWrites() {
        let markdown = """
        ## Features

        - **app:** check for updates
        - **dmg:** open the installer as a drag-to-Applications window

        ## Fixes

        - **core:** keep the Files tab responsive

        ## Other changes

        - write the full changelog
        """
        #expect(ReleaseNotes.parse(markdown) == [
            .init(title: "Features", items: [
                .init(scope: "app", text: "check for updates"),
                .init(scope: "dmg", text: "open the installer as a drag-to-Applications window"),
            ]),
            .init(title: "Fixes", items: [.init(scope: "core", text: "keep the Files tab responsive")]),
            .init(title: "Other changes", items: [.init(scope: nil, text: "write the full changelog")]),
        ])
    }

    @Test func bulletsBeforeAnyHeadingAndBlankNotesStillParse() {
        #expect(ReleaseNotes.parse("- fixed it\n* also this") == [
            .init(title: nil, items: [.init(scope: nil, text: "fixed it"), .init(scope: nil, text: "also this")]),
        ])
        #expect(ReleaseNotes.parse("  \n") == [])
    }

    @Test func plainLinesBecomeItemsAndEmptySectionsAreDropped() {
        #expect(ReleaseNotes.parse("## Empty\n\n## Notes\nA plain sentence.") == [
            .init(title: "Notes", items: [.init(scope: nil, text: "A plain sentence.")]),
        ])
    }
}
