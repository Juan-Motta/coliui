import Dispatch

/// Runs blocking work (socket reads, waiting on a process) on GCD threads.
/// Swift concurrency's cooperative pool has one thread per core: a dozen one-second Docker stats calls
/// blocking there would stall every other task in the app, the terminal's output included. GCD adds
/// threads for blocked work instead.
enum BlockingIO {
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// For readers that live as long as their stream; they end when their socket is shut down.
    static func start(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async(execute: work)
    }
}
