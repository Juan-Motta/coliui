import ColiUICore
import Foundation
import Observation

enum ImageFilter: String, CaseIterable {
    case all = "All"
    case used = "In use"
    case unused = "Unused"
    case dangling = "Dangling"
}

enum ImageSort: String, CaseIterable, Identifiable {
    case created = "Created"
    case repository = "Repository"
    case size = "Size"

    var id: Self { self }
}

/// Images.dc.html: one row per tag, which containers use each image, the pull bar.
@MainActor
@Observable
final class ImagesViewModel {
    private(set) var images: [DockerImage] = []
    @ObservationIgnored private var refreshes = LatestRequest()
    private(set) var isLoading = false
    var filter: ImageFilter = .all
    var sort: ImageSort = .created
    var searchText = ""
    var errorMessage: String?
    /// Set to ask for confirmation before removing.
    var pendingRemoval: DockerImage?
    private(set) var removingIDs: Set<String> = []
    var toast: String? { toasts.message }

    private(set) var isPullOpen = false
    var pullReference = ""
    private(set) var pullProgress: PullProgress?
    private(set) var pullError: String?
    var isPulling: Bool { pullTask != nil }
    /// Called with the reference and how long a successful pull took (Settings › Notifications).
    var onPullFinished: ((String, Duration) -> Void)?

    private let repository: ImageRepository
    private let puller: ImagePuller
    /// The container list the app already polls; used to tell which images are in use.
    private let containers: @MainActor () -> [Container]
    private let toasts: Toast
    private var pullTask: Task<Void, Never>?

    init(
        repository: ImageRepository,
        puller: ImagePuller,
        containers: @escaping @MainActor () -> [Container],
        toastDuration: Duration = .seconds(2)
    ) {
        self.repository = repository
        self.puller = puller
        self.containers = containers
        toasts = Toast(duration: toastDuration)
    }

    // MARK: Derived

    /// "8 images · 2.9 GB": each image once, however many tags it has.
    var summary: String {
        var sizes: [String: Int64] = [:]
        for image in images { sizes[image.imageID] = image.size }
        let count = sizes.count
        return "\(count) image\(count == 1 ? "" : "s") · \(ByteFormat.short(sizes.values.reduce(0, +)))"
    }

    /// Containers match by image ID; ones the engine reported without an ID match by reference.
    @ObservationIgnored private var usage = ContainerUsageIndex { [$0.imageID ?? "ref:" + $0.image] }

    func usedBy(_ image: DockerImage) -> [String] {
        let current = containers()
        let byID = usage.names(for: image.imageID, in: current)
        let byReference = usage.names(for: "ref:" + image.reference, in: current)
        guard !byReference.isEmpty else { return byID }
        return (byID + byReference).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func canRemove(_ image: DockerImage) -> Bool {
        usedBy(image).isEmpty
    }

    func count(for filter: ImageFilter) -> Int {
        images.filter { matches($0, filter) }.count
    }

    var visibleImages: [DockerImage] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return images
            .filter { matches($0, filter) }
            .filter {
                query.isEmpty
                    || $0.repository.localizedCaseInsensitiveContains(query)
                    || $0.tag.localizedCaseInsensitiveContains(query)
                    || $0.imageID.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                switch sort {
                case .created where lhs.created != rhs.created: lhs.created > rhs.created
                case .size where lhs.size != rhs.size: lhs.size > rhs.size
                default: "\(lhs.repository):\(lhs.tag)".localizedStandardCompare("\(rhs.repository):\(rhs.tag)") == .orderedAscending
                }
            }
    }

    private func matches(_ image: DockerImage, _ filter: ImageFilter) -> Bool {
        switch filter {
        case .all: true
        case .used: !canRemove(image)
        case .unused: canRemove(image) && !image.isDangling
        case .dangling: image.isDangling
        }
    }

    // MARK: Actions

    func refresh() async {
        isLoading = true
        let request = refreshes.next()
        do {
            let list = try await repository.images()
            guard refreshes.isLatest(request) else { return }
            images = list
            errorMessage = nil
        } catch {
            guard refreshes.isLatest(request) else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func remove(_ image: DockerImage) async {
        removingIDs.insert(image.id)
        defer { removingIDs.remove(image.id) }
        do {
            try await repository.removeImage(image.reference)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
        showToast("Removed \(image.isDangling ? image.shortID : image.reference)")
    }

    func openPull() {
        isPullOpen = true
        pullError = nil
    }

    func pull() async {
        let reference = pullReference.trimmingCharacters(in: .whitespaces)
        guard !reference.isEmpty, pullTask == nil else { return }
        pullError = nil
        pullProgress = PullProgress(phase: .waiting, fraction: nil)
        let started = ContinuousClock.now
        let task = Task { [puller] in
            do {
                for try await progress in puller.pull(reference) { pullProgress = progress }
                guard !Task.isCancelled else { return }
                onPullFinished?(reference, ContinuousClock.now - started)
                isPullOpen = false
                pullReference = ""
                showToast("Pulled \(reference)")
                await refresh()
            } catch {
                pullError = error.localizedDescription
            }
        }
        pullTask = task
        await task.value
        pullTask = nil
        pullProgress = nil
    }

    /// A click outside the modal: it closes, and a running pull keeps going (a notification says when it's done).
    func closePull() {
        isPullOpen = false
        if pullTask == nil { pullError = nil }
    }

    /// Stops a running pull; otherwise closes the modal.
    func cancelPull() {
        if let pullTask {
            pullTask.cancel()
        } else {
            isPullOpen = false
            pullError = nil
        }
    }

    func showToast(_ message: String) {
        toasts.show(message)
    }
}
