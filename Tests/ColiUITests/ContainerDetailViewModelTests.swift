import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeLogSource: ContainerLogSource, @unchecked Sendable {
    struct Call: Equatable { let id: String; let since: Date?; let tail: Int; let tty: Bool }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var lines: [LogLine]
    /// Like a followed stream: the history arrives, then the stream stays open.
    var keepsOpen = false
    /// The open stream, so a test can send more lines later.
    private(set) var live: AsyncThrowingStream<LogLine, Error>.Continuation?

    init(lines: [LogLine]) { self.lines = lines }

    var calls: [Call] { lock.withLock { _calls } }

    func logs(id: String, since: Date?, tail: Int, tty: Bool) -> AsyncThrowingStream<LogLine, Error> {
        lock.withLock { _calls.append(Call(id: id, since: since, tail: tail, tty: tty)) }
        let (lines, keepsOpen) = (lines, keepsOpen)
        return AsyncThrowingStream { continuation in
            lines.forEach { continuation.yield($0) }
            if keepsOpen { self.live = continuation } else { continuation.finish() }
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

/// Counts how many separate times `lines` changes, re-arming observation after each change.
@MainActor
private final class ChangeCounter {
    private(set) var count = 0

    func watch(_ model: ContainerDetailViewModel) {
        withObservationTracking { _ = model.lines } onChange: { [weak self] in
            Task { @MainActor in
                self?.count += 1
                self?.watch(model)
            }
        }
    }
}

@MainActor
@Suite struct ContainerDetailViewModelTests {
    /// Opening Logs used to add the history one line at a time, so the panel visibly scrolled
    /// through all of it; the history now lands in a few batches and the panel opens at the newest line.
    @Test func historyArrivesInBatches() async throws {
        let (model, source) = makeModel((0..<300).map { line($0, "line \($0)") })
        source.keepsOpen = true
        let counter = ChangeCounter()
        counter.watch(model)
        await model.start()
        for _ in 0..<40 where model.lines.count < 300 { try await Task.sleep(for: .milliseconds(10)) }

        #expect(model.lines.count == 300)
        #expect(counter.count <= 3)
        model.stop()
    }

    /// Closing the detail before its details arrive must not open a log stream nobody will close.
    @Test func stoppingBeforeStartFinishesOpensNoLogStream() async {
        let repository = FakeContainerRepository([])
        let gate = Gate()
        repository.detailsGate = gate
        let source = FakeLogSource(lines: [])
        let model = ContainerDetailViewModel(containerID: "c1", repository: repository, logSource: source, now: { now })

        let starting = Task { await model.start() }
        await Task.yield()
        model.stop()
        gate.release()
        await starting.value

        #expect(source.calls.isEmpty)
    }

    @Test func shellHereOpensTheTerminalInThatFolder() async {
        let connector = FakeShellConnector()
        let model = ContainerDetailViewModel(
            containerID: "c1", repository: FakeContainerRepository([]), logSource: FakeLogSource(lines: []),
            shellConnector: connector, now: { now }
        )
        model.openShell(in: "/app/my src")
        #expect(model.tab == .terminal)
        await model.terminal?.connect(columns: 80, rows: 24)
        #expect(connector.sessions[0].sent == [Data("cd -- '/app/my src'\n".utf8)])
    }

    @Test func startLoadsDetailsAndStreamsTheLast15Minutes() async {
        let (model, source) = makeModel([line(0, "Starting server", level: .info), line(1, "GET /health 200")])
        await model.start()
        await model.waitForLogs()

        #expect(model.details?.ipAddress == "172.17.0.4")
        #expect(model.lines.map(\.message) == ["Starting server", "GET /health 200"])
        #expect(source.calls == [.init(id: "c1", since: now.addingTimeInterval(-900), tail: 5000, tty: false)])
    }

    @Test func stoppedContainersOpenWithTheWholeHistory() async {
        let source = FakeLogSource(lines: [line(0, "Hello from Docker!")])
        let model = ContainerDetailViewModel(
            containerID: "c1",
            repository: FakeContainerRepository([]),
            logSource: source,
            range: .all,
            now: { now }
        )
        await model.start()
        await model.waitForLogs()

        #expect(model.range == .all)
        #expect(source.calls.map(\.since) == [nil])
        #expect(model.lines.map(\.message) == ["Hello from Docker!"])
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

    /// The filtered lines are kept up to date incrementally; they must always equal a full refilter.
    @Test func filteredLinesStayCorrectAsLinesArriveAndRollOff() async throws {
        let (model, source) = makeModel((0..<10).map { line($0, $0.isMultiple(of: 2) ? "GET /a \($0)" : "POST /b \($0)") })
        source.keepsOpen = true
        await model.start()
        func settle(_ count: Int) async throws {
            for _ in 0..<200 where model.lines.last?.id != count - 1 { try await Task.sleep(for: .milliseconds(10)) }
        }
        func reference() -> [Int] { model.lines.filter { $0.message.localizedCaseInsensitiveContains("get") }.map(\.id) }
        try await settle(10)
        model.filterText = "get"
        #expect(model.visibleLines.map(\.id) == reference())

        for id in 10..<5_020 { source.live?.yield(line(id, id.isMultiple(of: 3) ? "GET /c \(id)" : "PUT /d \(id)")) }
        try await settle(5_020)
        #expect(model.lines.first?.id == 20)
        #expect(model.visibleLines.map(\.id) == reference())

        model.useRegex = true
        model.filterText = "^put"
        #expect(model.visibleLines.map(\.id) == model.lines.filter { $0.message.hasPrefix("PUT") }.map(\.id))

        model.clear()
        #expect(model.visibleLines.isEmpty)
        source.live?.yield(line(5_020, "PUT /e"))
        try await settle(5_021)
        #expect(model.visibleLines.map(\.id) == [5_020])
        model.stop()
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
