import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private struct FakeVersions: ColimaVersionSource, EngineVersionSource {
    var colima: String?
    var engine: EngineVersion?

    func version() async throws -> String {
        guard let colima else { throw ColimaError.notInstalled }
        return colima
    }

    func engineVersion() async throws -> EngineVersion {
        guard let engine else { throw DockerError.socketUnavailable(path: "/x.sock") }
        return engine
    }
}

@MainActor
@Suite struct AboutViewModelTests {
    @Test func listsWhatThisMacRuns() async {
        let versions = FakeVersions(colima: "0.10.3", engine: EngineVersion(version: "29.5.2", apiVersion: "1.54"))
        let about = AboutViewModel(colima: versions, engine: versions, socketPath: "/Users/me/.colima/default/docker.sock",
                                   home: "/Users/me", appVersion: "0.1.0 (1)", system: "26.1 · Apple silicon")
        await about.load(profile: "default", vmType: "vz")

        #expect(about.rows.map(\.title) == ["Colima", "Docker Engine", "macOS", "Docker socket"])
        #expect(about.rows.map(\.value) == ["0.10.3 · profile default (vz)", "29.5.2 · API 1.54", "26.1 · Apple silicon", "~/.colima/default/docker.sock"])
        #expect(about.diagnostics == """
        ColiUI 0.1.0 (1)
        Colima: 0.10.3 · profile default (vz)
        Docker Engine: 29.5.2 · API 1.54
        macOS: 26.1 · Apple silicon
        Docker socket: ~/.colima/default/docker.sock
        """)
    }

    @Test func saysWhatCouldNotBeRead() async {
        let versions = FakeVersions(colima: nil, engine: nil)
        let about = AboutViewModel(colima: versions, engine: versions, socketPath: "/var/run/docker.sock",
                                   home: "/Users/me", appVersion: "0.1.0 (1)", system: "26.1")
        await about.load(profile: "default", vmType: nil)
        #expect(about.rows[0].value == "Not installed")
        #expect(about.rows[1].value == "Not reachable")
        #expect(about.rows[3].value == "/var/run/docker.sock")
    }
}
