import ColiUICore
import Foundation
import Observation

/// Files.dc.html: browse a container's folders, preview text files, download files and folders.
@MainActor
@Observable
final class FilesViewModel {
    enum State: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    enum Preview: Equatable {
        case none, loading, text(String), binary, tooLarge
        case failed(String)
    }

    /// Larger files are only downloaded, never fetched for the preview.
    static let previewLimit: Int64 = 256 * 1024

    var filter = ""
    var showHidden = false
    private(set) var path = "/"
    private(set) var state: State = .idle
    private(set) var entries: [ContainerFile] = []
    private(set) var selected: ContainerFile?
    private(set) var preview: Preview = .none
    /// A folder that couldn't be opened; the listing stays where it was.
    private(set) var notice: String?
    private var history: [String] = []
    /// Refreshes and folder changes overlap; only the newest listing is shown.
    @ObservationIgnored private var listings = LatestRequest()

    let containerID: String
    private let browser: ContainerFileBrowser

    init(containerID: String, browser: ContainerFileBrowser) {
        self.containerID = containerID
        self.browser = browser
    }

    /// The first time, opens the working directory; afterwards refreshes the current folder.
    func start() async {
        if state == .idle {
            path = (try? await browser.workingDirectory(id: containerID)) ?? "/"
        }
        await refresh()
    }

    func refresh() async {
        if entries.isEmpty { state = .loading }
        let request = listings.next()
        do {
            let listing = try await browser.listFiles(id: containerID, path: path)
            guard listings.isLatest(request) else { return }
            entries = listing
            state = .loaded
            if let selected, !entries.contains(where: { $0.name == selected.name }) { clearSelection() }
        } catch {
            guard listings.isLatest(request) else { return }
            entries = []
            state = .failed(error.localizedDescription)
        }
    }

    /// Opens a folder (or a link, which may point to one); a file is selected instead.
    func open(_ entry: ContainerFile) async {
        guard entry.kind == .directory || entry.kind == .symlink else { return await select(entry) }
        await go(to: ContainerPath.child(of: path, entry.name))
    }

    func go(to folder: String) async {
        guard folder != path else { return }
        let from = path
        if await show(folder) { history.append(from) }
    }

    var canGoBack: Bool { !history.isEmpty }
    var canGoUp: Bool { path != "/" }

    func goBack() async {
        guard let previous = history.last else { return }
        if await show(previous) { history.removeLast() }
    }

    func goUp() async {
        await go(to: ContainerPath.parent(of: path))
    }

    /// Lists `folder` and moves there; on failure stays put and says why.
    private func show(_ folder: String) async -> Bool {
        let request = listings.next()
        do {
            let listing = try await browser.listFiles(id: containerID, path: folder)
            guard listings.isLatest(request) else { return false }
            path = folder
            entries = listing
            state = .loaded
            notice = nil
            filter = ""
            clearSelection()
            return true
        } catch {
            if listings.isLatest(request) { notice = error.localizedDescription }
            return false
        }
    }

    var crumbs: [String] { ContainerPath.components(of: path) }

    var visibleEntries: [ContainerFile] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            (showHidden || !entry.isHidden) && (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query))
        }
    }

    var summary: String {
        let shown = entries.filter { showHidden || !$0.isHidden }.count
        let hidden = entries.count - shown
        return "\(shown) \(shown == 1 ? "item" : "items")" + (hidden > 0 ? " · \(hidden) hidden" : "")
    }

    var selectedPath: String? { selected.map { ContainerPath.child(of: path, $0.name) } }

    /// "Shell here": the selected folder, or the folder being shown.
    var shellFolder: String {
        if let selected, selected.kind == .directory, let selectedPath { return selectedPath }
        return path
    }

    func select(_ entry: ContainerFile) async {
        selected = entry
        guard entry.kind == .file else { preview = .none; return }
        guard entry.size <= Self.previewLimit else { preview = .tooLarge; return }
        preview = .loading
        let target = ContainerPath.child(of: path, entry.name)
        do {
            let data = try await browser.readFile(id: containerID, path: target)
            guard selectedPath == target else { return }
            if data.contains(0) { preview = .binary; return }
            guard let text = String(data: data, encoding: .utf8) else { preview = .binary; return }
            preview = .text(text)
        } catch {
            guard selectedPath == target else { return }
            preview = .failed(error.localizedDescription)
        }
    }

    func clearSelection() {
        selected = nil
        preview = .none
    }

    /// A file downloads as itself; a folder (the selected one, or the one shown) as a `.tar`.
    func download() async throws -> (filename: String, data: Data) {
        if let selected, selected.kind == .file, let selectedPath {
            return (selected.name, try await browser.readFile(id: containerID, path: selectedPath))
        }
        let folder = selected.flatMap { $0.kind == .directory ? selectedPath : nil } ?? path
        let name = ContainerPath.components(of: folder).last ?? "root"
        return (name + ".tar", try await browser.archive(id: containerID, path: folder))
    }
}
