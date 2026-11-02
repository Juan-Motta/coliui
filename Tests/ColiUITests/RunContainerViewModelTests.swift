import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeRunner: ContainerRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [RunRequest] = []
    var error: Error?

    var requests: [RunRequest] { lock.withLock { _requests } }

    func run(_ request: RunRequest) async throws -> String {
        lock.withLock { _requests.append(request) }
        if let error { throw error }
        return "abc123"
    }
}

@MainActor
private func filledForm(_ runner: FakeRunner = FakeRunner()) -> RunContainerViewModel {
    let model = RunContainerViewModel(runner: runner)
    model.image = "postgres:16-alpine"
    model.name = "postgres-test"
    model.ports = [PortRow(host: "5433", container: "5432", proto: "tcp"), PortRow()]
    model.volumes = [VolumeRow(source: "pgdata", target: "/var/lib/postgresql/data")]
    model.environment = [EnvRow(key: "POSTGRES_PASSWORD", value: "example"), EnvRow()]
    return model
}

@MainActor
@Suite struct RunContainerViewModelTests {
    @Test func defaultsFollowTheDesign() {
        let model = RunContainerViewModel(runner: FakeRunner())
        #expect(model.restartPolicy == .unlessStopped)
        #expect(model.pull)
        #expect(!model.autoRemove)
        #expect(model.ports.count == 1 && model.volumes.count == 1 && model.environment.count == 1)
    }

    @Test func buildsARequestWithoutEmptyRows() throws {
        let request = try #require(filledForm().request)
        #expect(request.ports == [PortBinding(hostPort: 5433, containerPort: 5432, proto: "tcp")])
        #expect(request.volumes == [VolumeBinding(source: "pgdata", target: "/var/lib/postgresql/data")])
        #expect(request.environment == [EnvironmentVariable(key: "POSTGRES_PASSWORD", value: "example")])
        #expect(request.name == "postgres-test")
    }

    @Test func emptyNameMeansDockerPicksOne() throws {
        let model = filledForm()
        model.name = "  "
        #expect(try #require(model.request).name == nil)
    }

    @Test(arguments: [
        ("image", "Enter an image, like nginx:latest."),
        ("name", "Names can use letters, digits, “_”, “.” and “-”, and must start with a letter or digit."),
        ("containerPort", "Container port must be a number from 1 to 65535."),
        ("hostPort", "Host port must be a number from 1 to 65535."),
        ("volume", "Each volume needs a source and an absolute container path."),
        ("envKey", "Each variable needs a name."),
        ("rmWithRestart", "“Remove when stopped” can't be combined with a restart policy."),
    ])
    func reportsTheFirstValidationProblem(field: String, message: String) {
        let model = filledForm()
        switch field {
        case "image": model.image = ""
        case "name": model.name = "-bad name"
        case "containerPort": model.ports = [PortRow(host: "8080", container: "", proto: "tcp")]
        case "hostPort": model.ports = [PortRow(host: "70000", container: "80", proto: "tcp")]
        case "volume": model.volumes = [VolumeRow(source: "data", target: "relative/path")]
        case "envKey": model.environment = [EnvRow(key: "", value: "x")]
        default:
            model.autoRemove = true
            model.restartPolicy = .always
        }
        #expect(model.validationError == message)
        #expect(model.request == nil)
    }

    @Test func runSendsTheRequestAndReportsSuccess() async {
        let runner = FakeRunner()
        let model = filledForm(runner)
        let started = await model.run()
        #expect(started == "postgres-test")
        #expect(runner.requests.count == 1)
        #expect(runner.requests.first?.pull == true)
        #expect(model.isRunning == false)
        #expect(model.errorMessage == nil)
    }

    @Test func invalidFormDoesNotRun() async {
        let runner = FakeRunner()
        let model = filledForm(runner)
        model.image = ""
        #expect(await model.run() == nil)
        #expect(runner.requests.isEmpty)
        #expect(model.showValidation)
    }

    @Test func runFailureKeepsTheForm() async {
        let runner = FakeRunner()
        runner.error = DockerError.requestFailed(status: 409, message: "Conflict. The container name is already in use")
        let model = filledForm(runner)
        #expect(await model.run() == nil)
        #expect(model.errorMessage == "Conflict. The container name is already in use")
        #expect(model.image == "postgres:16-alpine")
    }

    @Test func commandPreviewMasksSecrets() {
        let preview = filledForm().commandPreview
        #expect(preview.contains("-e POSTGRES_PASSWORD=••••••"))
        #expect(preview.hasPrefix("docker run -d --name postgres-test"))
        #expect(filledForm().commandToCopy.contains("POSTGRES_PASSWORD=example"))
    }

    @Test func parsesEnvFiles() {
        let text = """
        # database
        export DB_HOST=db
        DB_PASSWORD="s3cret value"
        EMPTY=
        NOT A VAR
        TOKEN='abc=123'
        """
        #expect(RunContainerViewModel.parseEnv(text) == [
            EnvironmentVariable(key: "DB_HOST", value: "db"),
            EnvironmentVariable(key: "DB_PASSWORD", value: "s3cret value"),
            EnvironmentVariable(key: "EMPTY", value: ""),
            EnvironmentVariable(key: "TOKEN", value: "abc=123"),
        ])
    }

    @Test func importingEnvReplacesTheEmptyRow() {
        let model = RunContainerViewModel(runner: FakeRunner())
        model.importEnv("A=1\nB=2")
        #expect(model.environment.map(\.key) == ["A", "B"])
    }
}
