import ColiUICore
import Foundation
import Observation

enum StatsRange: String, CaseIterable, Identifiable {
    case oneMinute = "1 min"
    case fiveMinutes = "5 min"
    case fifteenMinutes = "15 min"

    var id: Self { self }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
}

/// One plotted sample; I/O values are bytes per second.
struct StatsPoint: Equatable {
    let time: Date
    let cpu: Double
    let memory: Int64
    let received: Double
    let sent: Double
    let read: Double
    let written: Double
}

/// "42 KB/s · 18 KB/s": both values in the unit of the larger one, decimal like Finder.
enum RateFormat {
    static func pair(_ first: Double, _ second: Double) -> String {
        let peak = max(first, second)
        func format(_ value: Double) -> String {
            switch peak {
            case ..<1_000: "\(Int(value.rounded())) B/s"
            case ..<1_000_000: "\(Int((value / 1_000).rounded())) KB/s"
            default: String(format: "%.1f MB/s", value / 1_000_000)
            }
        }
        return "\(format(first)) · \(format(second))"
    }
}

/// Axis and hover labels: "3.1%", "214 MiB", "42 KB/s".
enum StatsValueFormat {
    static func percent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))%"
    }

    static func bytes(_ value: Double) -> String {
        guard value > 0 else { return "0" }
        let mib = value / 1_048_576
        if mib < 1024 { return "\(Int(mib.rounded())) MiB" }
        return String(format: "%.1f GiB", mib / 1024)
    }

    static func rate(_ value: Double) -> String {
        switch value {
        case ...0: "0"
        case ..<1_000: "\(Int(value.rounded())) B/s"
        case ..<1_000_000: "\(Int((value / 1_000).rounded())) KB/s"
        default: String(format: "%.1f MB/s", value / 1_000_000)
        }
    }
}

/// LiveStats.dc.html: samples one container every 2 s while visible and keeps 15 minutes of history.
@MainActor
@Observable
final class LiveStatsViewModel {
    static let history: TimeInterval = 15 * 60

    var range: StatsRange = .fiveMinutes
    private(set) var points: [StatsPoint] = []
    private(set) var latest: ContainerStats?
    private(set) var isPaused = false
    var isWindowHidden = false
    /// Where the pointer is over any chart; every chart marks the same moment.
    var hoveredTime: Date?
    private(set) var errorMessage: String?

    let containerID: String
    let interval: Duration
    private let repository: ContainerRepository
    private let now: () -> Date
    private var previous: (stats: ContainerStats, time: Date)?

    init(containerID: String, repository: ContainerRepository, interval: Duration = .seconds(2), now: @escaping () -> Date = Date.init) {
        self.containerID = containerID
        self.repository = repository
        self.interval = interval
        self.now = now
    }

    var isSampling: Bool { !isPaused && !isWindowHidden }

    func togglePause() {
        isPaused.toggle()
    }

    /// Runs until the task is cancelled (the Stats tab closes).
    func run() async {
        while !Task.isCancelled {
            if isSampling { await sampleOnce() }
            try? await Task.sleep(for: interval)
        }
    }

    func sampleOnce() async {
        do {
            record(try await repository.stats(id: containerID))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func record(_ stats: ContainerStats) {
        let time = stats.sampledAt ?? now()
        func rate(_ current: Int64, _ earlier: Int64?, _ elapsed: TimeInterval) -> Double {
            guard let earlier, elapsed > 0, current >= earlier else { return 0 } // first sample or restarted counters
            return Double(current - earlier) / elapsed
        }
        let elapsed = previous.map { time.timeIntervalSince($0.time) } ?? 0
        let earlier = previous?.stats
        points.append(StatsPoint(
            time: time,
            cpu: stats.cpuPercent,
            memory: stats.memoryBytes,
            received: rate(stats.networkReceived, earlier?.networkReceived, elapsed),
            sent: rate(stats.networkSent, earlier?.networkSent, elapsed),
            read: rate(stats.blockRead, earlier?.blockRead, elapsed),
            written: rate(stats.blockWritten, earlier?.blockWritten, elapsed)
        ))
        points.removeAll { time.timeIntervalSince($0.time) > Self.history }
        previous = (stats, time)
        latest = stats
    }

    var visiblePoints: [StatsPoint] {
        guard let end = points.last?.time else { return [] }
        return points.filter { end.timeIntervalSince($0.time) <= range.seconds }
    }

    var hoveredPoint: StatsPoint? {
        guard let hoveredTime else { return nil }
        return visiblePoints.min { abs($0.time.timeIntervalSince(hoveredTime)) < abs($1.time.timeIntervalSince(hoveredTime)) }
    }

    // MARK: Headlines

    var cpuValue: String { latest?.cpuDisplay ?? "—" }
    var cpuDetail: String {
        let cores = latest?.onlineCPUs ?? 0
        return cores > 0 ? "of \(cores) core\(cores == 1 ? "" : "s")" : ""
    }
    var memoryValue: String { latest?.memoryDisplay ?? "—" }
    var memoryDetail: String {
        guard let limit = latest?.memoryLimit else { return "" }
        let gib = Double(limit) / Double(1 << 30)
        if gib < 1 { return "limit \(limit >> 20) MiB" }
        return gib == gib.rounded() ? "limit \(Int(gib)) GiB" : String(format: "limit %.1f GiB", gib)
    }
    var networkValue: String {
        guard let point = points.last else { return "—" }
        return RateFormat.pair(point.received, point.sent)
    }
    var blockValue: String {
        guard let point = points.last else { return "—" }
        return RateFormat.pair(point.read, point.written)
    }
}
