import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeEnvironmentSource: ContainerEnvironmentSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var result: Result<[EnvironmentEntry], Error>

    init(_ result: Result<[EnvironmentEntry], Error>) { self.result = result }
    var calls: Int { lock.withLock { _calls } }

    func environment(id: String) async throws -> [EnvironmentEntry] {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

private let entries = EnvironmentEntry.list(
    container: ["PATH=/bin", "NODE_ENV=production", "DATABASE_URL=postgres://app:pw@db/shop", "JWT_SECRET=abc", "PORT=8080"],
    image: ["PATH=/bin"]
)

@MainActor
private func loaded() async -> EnvironmentViewModel {
    let model = EnvironmentViewModel(containerID: "c1", source: FakeEnvironmentSource(.success(entries)))
    await model.load()
    return model
}

@MainActor
@Suite struct EnvironmentViewModelTests {
    @Test func listsWithSecretsMasked() async {
        let model = await loaded()
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.name) == ["PATH", "NODE_ENV", "DATABASE_URL", "JWT_SECRET", "PORT"])
        #expect(model.rows.map(\.shownValue) == ["/bin", "production", "••••••", "••••••", "8080"])
        #expect(model.rows.map(\.source) == [.image, .container, .container, .container, .container])
        #expect(model.footnote == "2 secrets masked")
    }

    @Test func filtersBySourceWithCounts() async {
        let model = await loaded()
        #expect(model.count(of: .all) == 5)
        #expect(model.count(of: .container) == 4)
        #expect(model.count(of: .image) == 1)

        model.scope = .image
        #expect(model.rows.map(\.name) == ["PATH"])
    }

    @Test func filtersByNameOrValueButNotHiddenSecrets() async {
        let model = await loaded()
        model.filter = "prod"
        #expect(model.rows.map(\.name) == ["NODE_ENV"])
        model.filter = "secret"
        #expect(model.rows.map(\.name) == ["JWT_SECRET"])
        // A masked value can't be found by what it hides.
        model.filter = "postgres"
        #expect(model.rows.isEmpty)
        model.revealAll = true
        #expect(model.rows.map(\.name) == ["DATABASE_URL"])
    }

    @Test func revealsOneOrAllAndHidesAgain() async {
        let model = await loaded()
        model.toggleReveal("JWT_SECRET")
        #expect(model.rows.map(\.shownValue)[2...3] == ["••••••", "abc"])
        #expect(model.footnote == "1 secret masked")

        model.revealAll = true
        #expect(model.rows.map(\.shownValue)[2] == "postgres://app:pw@db/shop")
        #expect(model.footnote == "Secrets visible until you leave this tab")

        model.hideSecrets()
        #expect(!model.revealAll)
        #expect(model.rows.map(\.shownValue)[2...3] == ["••••••", "••••••"])
    }

    @Test func copiesAsDotEnvWhatIsShown() async {
        let model = await loaded()
        model.scope = .container
        #expect(model.dotEnv == "NODE_ENV=production\nDATABASE_URL=••••••\nJWT_SECRET=••••••\nPORT=8080\n")
        model.toggleReveal("JWT_SECRET")
        #expect(model.dotEnv.contains("JWT_SECRET=abc\n"))
    }

    @Test func rowCopyGivesTheRealValue() async {
        let model = await loaded()
        let row = try! #require(model.rows.first { $0.name == "JWT_SECRET" })
        #expect(row.value == "abc")
    }

    @Test func reportsFailuresAndReloads() async {
        let source = FakeEnvironmentSource(.failure(DockerError.requestFailed(status: 404, message: "No such container: c1")))
        let model = EnvironmentViewModel(containerID: "c1", source: source)
        await model.load()
        #expect(model.state == .failed("No such container: c1"))
        #expect(model.rows.isEmpty)

        source.result = .success(entries)
        await model.load()
        #expect(source.calls == 2)
        #expect(model.rows.count == 5)
    }
}
