import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeLogSource: ContainerLogSource, @unchecked Sendable {
    struct Call: Equatable { let id: String; let since: Date?; let tail: Int; let tty: Bool }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var lines: [LogLine]

    init(lines: [LogLine]) { self.lines = lines }

    var calls: [Call] { lock.withLock { _calls } }

    func logs(id: String, since: Date?, tail: Int, tty: Bool) -> AsyncThrowingStream<LogLine, Error> {
        lock.withLock { _calls.append(Call(id: id, since: since, tail: tail, tty: tty)) }
        let lines = lines
        return AsyncThrowingStream { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private func line(_ id: Int, _ message: String, level: LogLevel? = nil) -> LogLine {
    LogLine(id: id, timestamp: Date(timeIntervalSince1970: 1_793_500_000 + Double(id)), level: level, message: message, stream: .stdout)
}

private let now = Date(timeIntervalSince1970: 1_793_600_000)

@MainActor
private func makeModel(_ lines: [LogLine]) -> (ContainerDetailViewModel, FakeLogSource) {
    let source = FakeLogSource(lines: lines)
    let model = ContainerDetailViewModel(
        containerID: "c1",
        repository: FakeContainerRepository([]),
        logSource: source,
        now: { now }
    )
    return (model, source)
}

@MainActor
@Suite struct ContainerDetailViewModelTests {
    @Test func startLoadsDetailsAndStreamsTheLast15Minutes() async {
        let (model, source) = makeModel([line(0, "Starting server", level: .info), line(1, "GET /health 200")])
        await model.start()
        await model.waitForLogs()

        #expect(model.details?.ipAddress == "172.17.0.4")
        #expect(model.lines.map(\.message) == ["Starting server", "GET /health 200"])
        #expect(source.calls == [.init(id: "c1", since: now.addingTimeInterval(-900), tail: 5000, tty: false)])
    }

    @Test func plainFilterIsCaseInsensitive() async {
        let (model, _) = makeModel([line(0, "GET /health 200"), line(1, "POST /api/users 201"), line(2, "Slow query")])
        await model.start()
        await model.waitForLogs()

        model.filterText = "get"
        #expect(model.visibleLines.map(\.message) == ["GET /health 200"])
    }

    @Test func regexFilterMatchesPatterns() async {
        let (model, _) = makeModel([line(0, "GET /health 200"), line(1, "POST /api/users 201"), line(2, "GET /api/orders 500")])
        await model.start()
        await model.waitForLogs()

        model.useRegex = true
        model.filterText = #"/api/\w+ [25]0\d"#
        #expect(model.visibleLines.map(\.message) == ["POST /api/users 201", "GET /api/orders 500"])
        #expect(model.isRegexValid)
    }

    @Test func invalidRegexShowsNoLines() async {
        let (model, _) = makeModel([line(0, "anything")])
        await model.start()
        await model.waitForLogs()

        model.useRegex = true
        model.filterText = "(unclosed"
        #expect(!model.isRegexValid)
        #expect(model.visibleLines.isEmpty)
    }

    @Test func changingTheRangeRestartsTheStream() async {
        let (model, source) = makeModel([line(0, "a")])
        await model.start()
        await model.waitForLogs()

        model.select(range: .hour)
        await model.waitForLogs()
        model.select(range: .all)
        await model.waitForLogs()

        #expect(source.calls.map(\.since) == [now.addingTimeInterval(-900), now.addingTimeInterval(-3600), nil])
        #expect(model.lines.map(\.message) == ["a"])
    }

    @Test func keepsOnlyTheLast5000Lines() async {
        let (model, _) = makeModel((0..<5005).map { line($0, "line \($0)") })
        await model.start()
        await model.waitForLogs()

        #expect(model.lines.count == 5000)
        #expect(model.lines.first?.message == "line 5")
    }

    @Test func clearEmptiesTheBuffer() async {
        let (model, _) = makeModel([line(0, "a"), line(1, "b")])
        await model.start()
        await model.waitForLogs()

        model.clear()
        #expect(model.lines.isEmpty)
    }

    @Test func exportUsesVisibleLinesWithTimeAndLevel() async {
        let (model, _) = makeModel([line(0, "Starting", level: .info), line(1, "no level")])
        await model.start()
        await model.waitForLogs()

        let lines = model.exportText().split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" INFO Starting"))
        #expect(lines[1].hasSuffix(" no level"))
        #expect(lines[0].hasPrefix("2026-"))
    }
}
