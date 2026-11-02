import Observation

/// A short confirmation ("Copied …") that hides itself after `duration`; a new one replaces the current one.
@MainActor
@Observable
final class Toast {
    private(set) var message: String?
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(duration: Duration) {
        self.duration = duration
    }

    func show(_ message: String) {
        self.message = message
        hideTask?.cancel()
        guard duration > .zero else { return }
        let duration = duration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
