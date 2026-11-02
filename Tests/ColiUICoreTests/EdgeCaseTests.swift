import Foundation
import Testing
@testable import ColiUICore

/// Edge cases found in the 2026-11-02 review.
@Suite struct EdgeCaseTests {
    private func binds(_ source: String) -> [String] {
        let request = RunRequest(image: "nginx", name: nil, ports: [], volumes: [VolumeBinding(source: source, target: "/data")],
                                 environment: [], restartPolicy: .no, autoRemove: false, pull: false)
        let host = DockerEngineRepository.createBody(request)["HostConfig"] as? [String: Any]
        return host?["Binds"] as? [String] ?? []
    }

    @Test func onlyTildeAndTildeSlashMeanHome() {
        let home = NSHomeDirectory()
        #expect(binds("~") == ["\(home):/data"])
        #expect(binds("~/code") == ["\(home)/code:/data"])
        // `~other` is another user's home in a shell; never glue it onto ours.
        #expect(binds("~other/code") == ["~other/code:/data"])
    }

    @Test(arguments: ["caf\u{E9}", "\u{0663}", "api\u{2010}server"])
    func identifiersAreASCIIOnly(_ id: String) {
        #expect(throws: DockerError.invalidContainerID) { try DockerEngineRepository.validated(id) }
        #expect(throws: DockerError.invalidContainerID) { try DockerEngineRepository.validatedImageReference(id) }
    }

    @Test func aHugeChunkSizeIsRejectedNotACrash() {
        let raw = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7fffffffffffffff\r\nabc\r\n0\r\n\r\n".utf8)
        #expect(throws: DockerError.malformedResponse) { try HTTPMessage.parseResponse(raw) }
    }

    @Test func aLoneHighSurrogateKeepsTheNextEscape() throws {
        #expect(try JSONValue.parse(Data(#"["\uD800A"]"#.utf8)) == .array([.string("\u{FFFD}A")]))
    }
}
