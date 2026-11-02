import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeImageRepository: ImageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _removed: [String] = []
    private var _loads = 0
    var images: [DockerImage]
    var removeError: Error?

    init(images: [DockerImage]) { self.images = images }

    var removed: [String] { lock.withLock { _removed } }
    var loads: Int { lock.withLock { _loads } }

    func images() async throws -> [DockerImage] {
        lock.withLock { _loads += 1 }
        return images
    }

    func removeImage(_ reference: String) async throws {
        if let removeError { throw removeError }
        lock.withLock { _removed.append(reference) }
    }
}

final class FakeImagePuller: ImagePuller, @unchecked Sendable {
    private let lock = NSLock()
    private var _pulled: [String] = []
    var steps: [PullProgress] = []
    var error: Error?
    /// Keeps the stream open until cancelled.
    var hangs = false

    var pulled: [String] { lock.withLock { _pulled } }

    func pull(_ reference: String) -> AsyncThrowingStream<PullProgress, Error> {
        lock.withLock { _pulled.append(reference) }
        let (steps, error, hangs) = (steps, error, hangs)
        return AsyncThrowingStream { continuation in
            steps.forEach { continuation.yield($0) }
            if hangs { return }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func image(_ id: String, _ repository: String, _ tag: String, age: TimeInterval, size: Int64) -> DockerImage {
    DockerImage(imageID: "sha256:\(id)", repository: repository, tag: tag, created: now.addingTimeInterval(-age), size: size)
}

private let api = image("aaa111", "myapp/api", "latest", age: 600, size: 412_000_000)
private let apiOld = image("aaa111", "myapp/api", "1.2", age: 600, size: 412_000_000)
private let node = image("bbb222", "node", "22-alpine", age: 5_000_000, size: 1_100_000_000)
private let dangling = image("ccc333", "<none>", "<none>", age: 400_000, size: 386_000_000)

private let apiServer = Container(id: "e81b", name: "api-server", image: "myapp/api:latest", state: .running,
                                  status: "Up", imageID: "sha256:aaa111")
private let apiWorker = Container(id: "f92c", name: "api-worker", image: "myapp/api:latest", state: .exited,
                                  status: "Exited (0)", imageID: "sha256:aaa111")

@MainActor
private func makeModel(
    images: [DockerImage] = [api, apiOld, node, dangling],
    containers: [Container] = [apiServer, apiWorker],
    puller: FakeImagePuller = FakeImagePuller()
) -> (ImagesViewModel, FakeImageRepository) {
    let repository = FakeImageRepository(images: images)
    let model = ImagesViewModel(repository: repository, puller: puller, containers: { containers }, toastDuration: .zero)
    return (model, repository)
}

@MainActor
@Suite struct ImagesViewModelTests {
    @Test func summarisesUniqueImagesAndCountsFilters() async {
        let (model, _) = makeModel()
        await model.refresh()

        #expect(model.summary == "3 images · 1.9 GB")
        #expect(model.count(for: .all) == 4)
        #expect(model.count(for: .used) == 2)
        #expect(model.count(for: .unused) == 1)
        #expect(model.count(for: .dangling) == 1)
        #expect(model.usedBy(api) == ["api-server", "api-worker"])
        #expect(model.usedBy(node).isEmpty)
        #expect(!model.canRemove(api))
        #expect(model.canRemove(node))
    }

    @Test func listsNewestFirstAndFiltersBySearchAndUse() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.visibleImages.map(\.id) == [apiOld.id, api.id, dangling.id, node.id])

        model.sort = .size
        #expect(model.visibleImages.first == node)
        model.sort = .repository
        #expect(model.visibleImages.map(\.repository) == ["<none>", "myapp/api", "myapp/api", "node"])

        model.filter = .unused
        #expect(model.visibleImages == [node])
        model.filter = .all
        model.searchText = "API"
        #expect(model.visibleImages.map(\.tag).sorted() == ["1.2", "latest"])
    }

    @Test func removesByReferenceThenRefreshes() async {
        let (model, repository) = makeModel()
        await model.refresh()
        await model.remove(node)

        #expect(repository.removed == ["node:22-alpine"])
        #expect(repository.loads == 2)
        #expect(model.toast == "Removed node:22-alpine")
        await model.remove(dangling)
        #expect(repository.removed.last == "ccc333")
    }

    @Test func keepsTheRemoveErrorAfterTheRefresh() async {
        let (model, repository) = makeModel()
        repository.removeError = DockerError.requestFailed(status: 409, message: "image is being used by stopped container f92c")
        await model.remove(node)

        #expect(model.errorMessage == "image is being used by stopped container f92c")
        #expect(repository.loads == 0)
    }

    @Test func pullsShowsProgressThenClosesTheBar() async {
        let puller = FakeImagePuller()
        puller.steps = [PullProgress(phase: .downloading, fraction: 0.62), PullProgress(phase: .done, fraction: 1)]
        let (model, repository) = makeModel(puller: puller)
        model.openPullBar()
        model.pullReference = "  python:3.13-slim "
        await model.pull()

        #expect(puller.pulled == ["python:3.13-slim"])
        #expect(!model.isPullBarOpen)
        #expect(!model.isPulling)
        #expect(model.pullReference == "")
        #expect(model.toast == "Pulled python:3.13-slim")
        #expect(repository.loads == 1)
    }

    @Test func pullErrorsStayInTheBar() async {
        let puller = FakeImagePuller()
        puller.error = DockerError.requestFailed(status: 200, message: "manifest unknown")
        let (model, _) = makeModel(puller: puller)
        model.openPullBar()
        model.pullReference = "nope:404"
        await model.pull()

        #expect(model.isPullBarOpen)
        #expect(model.pullError == "manifest unknown")
        #expect(model.pullProgress == nil)
    }

    @Test func emptyReferenceDoesNotPull() async {
        let puller = FakeImagePuller()
        let (model, _) = makeModel(puller: puller)
        model.openPullBar()
        await model.pull()
        #expect(puller.pulled.isEmpty)
    }

    @Test func cancelStopsARunningPullThenClosesTheBar() async throws {
        let puller = FakeImagePuller()
        puller.steps = [PullProgress(phase: .downloading, fraction: 0.1)]
        puller.hangs = true
        let (model, repository) = makeModel(puller: puller)
        model.openPullBar()
        model.pullReference = "python:3.13-slim"
        let pull = Task { await model.pull() }
        while model.pullProgress?.fraction != 0.1 { await Task.yield() }

        model.cancelPull()
        await pull.value
        #expect(!model.isPulling)
        #expect(model.pullProgress == nil)
        #expect(model.isPullBarOpen)
        #expect(model.toast == nil)
        #expect(repository.loads == 0)

        model.cancelPull()
        #expect(!model.isPullBarOpen)
    }
}
