/// Numbers overlapping requests so only the newest applies its answer.
/// The poll, Docker events and user actions refresh at the same time, and answers can come back out of order.
struct LatestRequest {
    private var latest = 0

    /// Starts a request; keep the number and check it when the answer arrives.
    mutating func next() -> Int {
        latest += 1
        return latest
    }

    func isLatest(_ request: Int) -> Bool { request == latest }
}
