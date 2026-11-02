import ColiUICore
import Foundation
import Testing
@testable import ColiUI

final class FakeFileBrowser: ContainerFileBrowser, @unchecked Sendable {
    private let lock = NSLock()
    private var _listed: [String] = []
    private var _read: [String] = []
    var folders: [String: [ContainerFile]]
    var contents: [String: Data] = [:]
    var start = "/app"
    var listError: Error?
    /// When set for a path, its listing waits for the gate.
    var listGates: [String: Gate] = [:]

    init(_ folders: [String: [ContainerFile]]) { self.folders = folders }
    var listed: [String] { lock.withLock { _listed } }
    var read: [String] { lock.withLock { _read } }

    func workingDirectory(id: String) async throws -> String { start }

    func listFiles(id: String, path: String) async throws -> [ContainerFile] {
        lock.withLock { _listed.append(path) }
        let (files, gate) = lock.withLock { (folders[path], listGates.removeValue(forKey: path)) }
        await gate?.wait()
        if let listError { throw listError }
        guard let files else { throw ContainerFilesError.cannotOpen(path: path, reason: "No such file or directory") }
        return files
    }

    func readFile(id: String, path: String) async throws -> Data {
        lock.withLock { _read.append(path) }
        return contents[path] ?? Data()
    }

    var archiveGate: Gate?
    var archiveError: Error?

    func archive(id: String, path: String) async throws -> Data {
        await archiveGate?.wait()
        if let archiveError { throw archiveError }
        return Data("tar of \(path)".utf8)
    }
}

private let date = Date(timeIntervalSince1970: 1_793_500_000)
private func dir(_ name: String) -> ContainerFile { ContainerFile(name: name, kind: .directory, size: 4096, modified: date, mode: "drwxr-xr-x", owner: "root:root") }
private func file(_ name: String, _ size: Int64 = 10) -> ContainerFile { ContainerFile(name: name, kind: .file, size: size, modified: date, mode: "-rw-r--r--", owner: "node:node") }

private func browser() -> FakeFileBrowser {
    let fake = FakeFileBrowser([
        "/": [dir("app"), dir("etc")],
        "/app": [dir("src"), file(".env"), file("package.json"), file("server.log", 18_000_000), file("logo.png")],
        "/app/src": [file("server.ts")],
    ])
    fake.contents = [
        "/app/package.json": Data(#"{"name":"api"}"#.utf8),
        "/app/logo.png": Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]),
    ]
    return fake
}

@MainActor
private func started(_ fake: FakeFileBrowser = browser()) async -> FilesViewModel {
    let model = FilesViewModel(containerID: "c1", browser: fake)
    await model.start()
    return model
}

@MainActor
@Suite struct FilesViewModelTests {
    @Test func startsInTheWorkingDirectoryHidingDotFiles() async {
        let model = await started()
        #expect(model.path == "/app")
        #expect(model.state == .loaded)
        #expect(model.visibleEntries.map(\.name) == ["src", "package.json", "server.log", "logo.png"])
        #expect(model.summary == "4 items · 1 hidden")

        model.showHidden = true
        #expect(model.visibleEntries.map(\.name).contains(".env"))
        #expect(model.summary == "5 items")
    }

    @Test func opensFoldersAndGoesBackAndUp() async {
        let fake = browser()
        let model = await started(fake)

        await model.open(model.visibleEntries[0])
        #expect(model.path == "/app/src")
        #expect(model.crumbs == ["app", "src"])
        #expect(model.canGoBack)

        await model.goUp()
        #expect(model.path == "/app")
        await model.goUp()
        #expect(model.path == "/")
        #expect(!model.canGoUp)

        await model.goBack()
        #expect(model.path == "/app")
        await model.goBack()
        #expect(model.path == "/app/src")
        #expect(fake.listed == ["/app", "/app/src", "/app", "/", "/app", "/app/src"])
    }

    @Test func crumbsJumpToAFolder() async {
        let model = await started()
        await model.go(to: "/")
        #expect(model.path == "/")
        #expect(model.crumbs.isEmpty)
    }

    @Test func filtersByName() async {
        let model = await started()
        model.filter = "PACK"
        #expect(model.visibleEntries.map(\.name) == ["package.json"])
    }

    @Test func previewsSmallTextFiles() async {
        let model = await started()
        await model.select(model.visibleEntries.first { $0.name == "package.json" }!)
        #expect(model.preview == .text(#"{"name":"api"}"#))
        #expect(model.selectedPath == "/app/package.json")
    }

    @Test func doesNotFetchLargeFiles() async {
        let fake = browser()
        let model = await started(fake)
        await model.select(model.visibleEntries.first { $0.name == "server.log" }!)
        #expect(model.preview == .tooLarge)
        #expect(fake.read.isEmpty)
    }

    @Test func recognisesBinaryFiles() async {
        let model = await started()
        await model.select(model.visibleEntries.first { $0.name == "logo.png" }!)
        #expect(model.preview == .binary)
    }

    @Test func foldersHaveNoContentPreview() async {
        let model = await started()
        await model.select(model.visibleEntries[0])
        #expect(model.preview == .none)
        #expect(model.selected?.name == "src")
    }

    @Test func downloadsAFileOrAFolderAsTar() async throws {
        let model = await started()
        await model.select(model.visibleEntries.first { $0.name == "package.json" }!)
        let fileDownload = try #require(await model.download())
        #expect(fileDownload.filename == "package.json")
        #expect(fileDownload.data == Data(#"{"name":"api"}"#.utf8))

        await model.select(model.visibleEntries[0])
        let folderDownload = try #require(await model.download())
        #expect(folderDownload.filename == "src.tar")
        #expect(folderDownload.data == Data("tar of /app/src".utf8))

        model.clearSelection()
        #expect(await model.download()?.filename == "app.tar")
    }

    /// A big folder takes a while: a second click doesn't start another download, and a failure says why.
    @Test func oneDownloadAtATimeAndFailuresAreShown() async {
        let fake = browser()
        let gate = Gate()
        fake.archiveGate = gate
        let model = await started(fake)
        let first = Task { await model.download() }
        for _ in 0..<1_000 where !model.isDownloading { await Task.yield() }
        #expect(model.isDownloading)
        #expect(await model.download() == nil)
        gate.release()
        #expect(await first.value?.filename == "app.tar")
        #expect(!model.isDownloading)

        fake.archiveError = ContainerFilesError.cannotOpen(path: "/app", reason: "Permission denied")
        #expect(await model.download() == nil)
        #expect(model.notice == "Can't open /app: Permission denied")
    }

    @Test func shellFolderIsTheSelectedFolderOrTheCurrentOne() async {
        let model = await started()
        #expect(model.shellFolder == "/app")
        await model.select(model.visibleEntries[0])
        #expect(model.shellFolder == "/app/src")
        await model.select(model.visibleEntries.first { $0.name == "package.json" }!)
        #expect(model.shellFolder == "/app")
    }

    @Test func showsWhyAFolderCantBeListed() async {
        let fake = browser()
        fake.listError = ContainerFilesError.noShell
        let model = await started(fake)
        #expect(model.state == .failed("This container has no shell (sh) or stat command, so its files can't be listed."))
        #expect(model.visibleEntries.isEmpty)
    }

    /// Reopening the tab refreshes the old folder while the user already moved on.
    @Test func aLateRefreshDoesNotReplaceTheFolderYouOpened() async {
        let fake = browser()
        let model = await started(fake)
        let gate = Gate()
        fake.listGates["/app"] = gate
        let refreshing = Task { await model.refresh() }
        await Task.yield()
        await model.go(to: "/app/src")
        gate.release()
        await refreshing.value

        #expect(model.path == "/app/src")
        #expect(model.visibleEntries.map(\.name) == ["server.ts"])
    }

    @Test func theLastFolderYouOpenedWins() async {
        let fake = browser()
        let model = await started(fake)
        let gate = Gate()
        fake.listGates["/"] = gate
        let slow = Task { await model.go(to: "/") }
        await Task.yield()
        await model.go(to: "/app/src")
        gate.release()
        await slow.value

        #expect(model.path == "/app/src")
        #expect(model.visibleEntries.map(\.name) == ["server.ts"])
    }

    /// Going up fails while the first listing is still loading: the tab must not stay on "Loading…".
    @Test func aFailedMoveDuringTheFirstLoadStillShowsTheFolder() async {
        let fake = FakeFileBrowser(["/app/src": [file("a.txt")]])
        fake.start = "/app/src"
        let gate = Gate()
        fake.listGates["/app/src"] = gate
        let model = FilesViewModel(containerID: "c1", browser: fake)
        let starting = Task { await model.start() }
        for _ in 0..<1_000 where model.state != .loading { await Task.yield() }
        await model.goUp()
        gate.release()
        await starting.value
        for _ in 0..<1_000 where model.state != .loaded { await Task.yield() }

        #expect(model.state == .loaded)
        #expect(model.path == "/app/src")
        #expect(model.visibleEntries.map(\.name) == ["a.txt"])
        #expect(model.notice == "Can't open /app: No such file or directory")
    }

    @Test func aFolderThatFailsToOpenKeepsYouWhereYouWere() async {
        let model = await started()
        await model.go(to: "/missing")
        #expect(model.path == "/app")
        #expect(model.state == .loaded)
        #expect(model.notice == "Can't open /missing: No such file or directory")
    }
}
