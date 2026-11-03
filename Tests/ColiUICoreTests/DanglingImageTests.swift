import Foundation
import Testing
@testable import ColiUICore

private func ok(_ body: String = "[]") -> HTTPResponse {
    HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
}

/// `/images/json?all=1` rows: id, parent, tags.
private func list(_ rows: [(String, String, [String])]) -> HTTPResponse {
    let json = rows.map { id, parent, tags in
        let tagList = tags.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"Id":"sha256:\#(id)","ParentId":"\#(parent.isEmpty ? "" : "sha256:" + parent)","RepoTags":[\#(tagList)],"Created":0,"Size":1}"#
    }
    return ok("[" + json.joined(separator: ",") + "]")
}

@Suite struct DanglingImageTests {
    private let top = String(repeating: "a", count: 64)
    private let middle = String(repeating: "b", count: 64)
    private let bottom = String(repeating: "c", count: 64)
    private let base = String(repeating: "d", count: 64)

    /// A multi-step `docker build` leaves untagged layers under its result. Docker hides the ones with a child,
    /// so removing the top one used to reveal the next as a "new" dangling image that looked like the same one.
    @Test func removingADanglingImageAlsoRemovesTheUntaggedLayersItLeavesBehind() async throws {
        let transport = FakeTransport(response: ok())
        transport.scripted["/images/json"] = [
            list([(top, middle, []), (middle, bottom, []), (bottom, base, []), (base, "", ["alpine:3"])]),
            list([(middle, bottom, []), (bottom, base, []), (base, "", ["alpine:3"])]),
            list([(bottom, base, []), (base, "", ["alpine:3"])]),
        ]
        let repository = DockerEngineRepository(transport: transport)

        let parents = try await repository.removeDanglingImage(id: "sha256:" + top)

        #expect(parents == 2)
        #expect(transport.calls.filter { $0.method == "DELETE" }.map(\.path) == [
            "/images/\(top)?force=false", "/images/\(middle)?force=false", "/images/\(bottom)?force=false",
        ])
    }

    @Test func itStopsAtATaggedLayerOrOneAnotherImageStillBuildsOn() async throws {
        let sibling = String(repeating: "e", count: 64)
        let transport = FakeTransport(response: ok())
        transport.scripted["/images/json"] = [
            list([(top, middle, []), (middle, base, []), (sibling, middle, ["app:2"]), (base, "", ["alpine:3"])]),
            // After the delete, `middle` still has `sibling` on top of it.
            list([(middle, base, []), (sibling, middle, ["app:2"]), (base, "", ["alpine:3"])]),
        ]
        let repository = DockerEngineRepository(transport: transport)

        #expect(try await repository.removeDanglingImage(id: top) == 0)
        #expect(transport.calls.filter { $0.method == "DELETE" }.map(\.path) == ["/images/\(top)?force=false"])
    }

    @Test func aLayerAContainerUsesStopsTheWalkWithoutFailing() async throws {
        let transport = FakeTransport(response: ok())
        transport.scripted["/images/json"] = [
            list([(top, middle, []), (middle, "", [])]),
            list([(middle, "", [])]),
        ]
        transport.scripted["/images/\(middle)"] = [
            HTTPResponse(statusCode: 409, headers: [:], body: Data(#"{"message":"image is being used by stopped container"}"#.utf8)),
        ]
        let repository = DockerEngineRepository(transport: transport)

        #expect(try await repository.removeDanglingImage(id: top) == 0)
    }

    @Test func aFailedDeleteOfTheImageItselfIsReported() async {
        let transport = FakeTransport(response: ok())
        transport.scripted["/images/json"] = [list([(top, "", [])])]
        transport.scripted["/images/\(top)"] = [
            HTTPResponse(statusCode: 409, headers: [:], body: Data(#"{"message":"conflict"}"#.utf8)),
        ]
        let repository = DockerEngineRepository(transport: transport)

        await #expect(throws: DockerError.requestFailed(status: 409, message: "conflict")) {
            try await repository.removeDanglingImage(id: top)
        }
    }
}
