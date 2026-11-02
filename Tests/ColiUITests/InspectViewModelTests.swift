import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeInspector: ContainerInspector, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var result: Result<JSONValue, Error>

    init(_ result: Result<JSONValue, Error>) { self.result = result }
    var calls: Int { lock.withLock { _calls } }

    func inspect(id: String) async throws -> JSONValue {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

private let sample = JSONValue.object([
    JSONMember(key: "Id", value: .string("c1")),
    JSONMember(key: "State", value: .object([
        JSONMember(key: "Running", value: .bool(true)),
        JSONMember(key: "Pid", value: .number("42")),
        JSONMember(key: "Error", value: .null),
    ])),
    JSONMember(key: "Args", value: .array([.string("node")])),
    JSONMember(key: "HostConfig", value: .object([
        JSONMember(key: "NetworkMode", value: .string("bridge")),
        JSONMember(key: "Memory", value: .number("0")),
    ])),
])

/// "key: value summary" per row, indented two spaces per level, for readable expectations.
@MainActor
private func lines(_ model: InspectViewModel) -> [String] {
    model.rows.map { row in
        let key = row.key.map { "\($0): " } ?? ""
        let text = key + [row.value, row.summary].filter { !$0.isEmpty }.joined(separator: " ")
        return String(repeating: "  ", count: row.depth) + text
    }
}

@MainActor
@Suite struct InspectViewModelTests {
    @Test func loadsWithTheDesignsBranchesOpen() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.success(sample)))
        await model.load()

        #expect(model.state == .loaded)
        #expect(lines(model) == [
            "{",
            "  \"Id\": \"c1\"",
            "  \"State\": {",
            "    \"Running\": true",
            "    \"Pid\": 42",
            "    \"Error\": null",
            "  }",
            "  \"Args\": [ 1 item ]",
            "  \"HostConfig\": { 2 keys }",
            "}",
        ])
        #expect(model.rows.map(\.kind)[1...5] == [.string, .open, .bool, .number, .null])
    }

    @Test func togglesABranch() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.success(sample)))
        await model.load()
        let hostConfig = try! #require(model.rows.first { $0.key == "\"HostConfig\"" })
        #expect(hostConfig.isBranch && !hostConfig.isExpanded)

        model.toggle(hostConfig)
        #expect(lines(model).suffix(5) == ["  \"HostConfig\": {", "    \"NetworkMode\": \"bridge\"", "    \"Memory\": 0", "  }", "}"])
        model.toggle(try! #require(model.rows.first { $0.key == "\"State\"" }))
        #expect(lines(model)[2] == "  \"State\": { 3 keys }")
    }

    @Test func expandsAndCollapsesEverything() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.success(sample)))
        await model.load()

        model.expandAll()
        #expect(model.rows.filter { $0.isBranch && !$0.isExpanded }.isEmpty)
        #expect(lines(model).contains("    0: \"node\""))

        model.collapseAll()
        #expect(lines(model) == ["{", "  \"Id\": \"c1\"", "  \"State\": { 3 keys }", "  \"Args\": [ 1 item ]", "  \"HostConfig\": { 2 keys }", "}"])
    }

    @Test func filterKeepsMatchesAndTheirParents() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.success(sample)))
        await model.load()

        model.filter = "bridge"
        #expect(lines(model) == ["{", "  \"HostConfig\": {", "    \"NetworkMode\": \"bridge\""])

        model.filter = "state"
        #expect(lines(model) == ["{", "  \"State\": {", "    \"Running\": true", "    \"Pid\": 42", "    \"Error\": null", "  }"])

        model.filter = "nothing-matches"
        #expect(model.rows.isEmpty)
    }

    @Test func rawIsWrappedLikeDockerInspect() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.success(.object([JSONMember(key: "Id", value: .string("c1"))]))))
        await model.load()
        #expect(model.rawJSON == "[\n  {\n    \"Id\": \"c1\"\n  }\n]")
    }

    @Test func copiesPlainValues() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.success(sample)))
        await model.load()
        #expect(model.rows.first { $0.key == "\"Id\"" }?.copyText == "c1")
        #expect(model.rows.first { $0.key == "\"Pid\"" }?.copyText == "42")
        #expect(model.rows.first { $0.key == "\"State\"" }?.copyText == nil)
    }

    @Test func reportsFailures() async {
        let model = InspectViewModel(containerID: "c1", inspector: FakeInspector(.failure(DockerError.requestFailed(status: 404, message: "No such container: c1"))))
        await model.load()
        #expect(model.state == .failed("No such container: c1"))
        #expect(model.rows.isEmpty)
    }

    @Test func reloadsKeepingWhatTheUserOpened() async {
        let inspector = FakeInspector(.success(sample))
        let model = InspectViewModel(containerID: "c1", inspector: inspector)
        await model.load()
        model.toggle(try! #require(model.rows.first { $0.key == "\"HostConfig\"" }))
        await model.load()
        #expect(inspector.calls == 2)
        #expect(model.rows.contains { $0.key == "\"NetworkMode\"" })
    }
}
