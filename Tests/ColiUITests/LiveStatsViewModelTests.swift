import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func sample(at seconds: TimeInterval, cpu: Double = 3.1, memory: Int64 = 214 << 20,
                    rx: Int64 = 0, tx: Int64 = 0, read: Int64 = 0, write: Int64 = 0) -> ContainerStats {
    ContainerStats(cpuPercent: cpu, memoryBytes: memory, onlineCPUs: 4, memoryLimit: 1 << 30,
                   networkReceived: rx, networkSent: tx, blockRead: read, blockWritten: write,
                   sampledAt: t0.addingTimeInterval(seconds))
}

@MainActor
private func makeModel() -> LiveStatsViewModel {
    LiveStatsViewModel(containerID: "c1", repository: FakeContainerRepository([]))
}

@MainActor
@Suite struct LiveStatsViewModelTests {
    @Test func ratesComeFromConsecutiveSamples() {
        let model = makeModel()
        model.record(sample(at: 0, rx: 1_000, tx: 1_000, read: 0, write: 0))
        model.record(sample(at: 2, rx: 85_000, tx: 37_000, read: 2_400_000, write: 600_000))

        let last = model.points.last!
        #expect(last.received == 42_000)
        #expect(last.sent == 18_000)
        #expect(last.read == 1_200_000)
        #expect(last.written == 300_000)
        #expect(model.networkValue == "42 KB/s · 18 KB/s")
        #expect(model.blockValue == "1.2 MB/s · 0.3 MB/s")
    }

    @Test func firstSampleAndCounterResetsReadAsZeroRate() {
        let model = makeModel()
        model.record(sample(at: 0, rx: 5_000))
        #expect(model.points.last?.received == 0)
        model.record(sample(at: 2, rx: 100))
        #expect(model.points.last?.received == 0)
    }

    @Test func headlineValues() {
        let model = makeModel()
        #expect(model.cpuValue == "—")
        model.record(sample(at: 0))
        #expect(model.cpuValue == "3.1%")
        #expect(model.cpuDetail == "of 4 cores")
        #expect(model.memoryValue == "214 MiB")
        #expect(model.memoryDetail == "limit 1 GiB")
    }

    @Test func keepsFifteenMinutesAndShowsTheSelectedRange() {
        let model = makeModel()
        for second in stride(from: 0, through: 1_200, by: 2) {
            model.record(sample(at: TimeInterval(second)))
        }
        #expect(model.points.first!.time == t0.addingTimeInterval(300))
        #expect(model.range == .fiveMinutes)
        #expect(model.visiblePoints.count == 151)
        model.range = .oneMinute
        #expect(model.visiblePoints.count == 31)
    }

    @Test func samplingStopsWhilePausedOrHidden() async {
        let model = makeModel()
        #expect(model.isSampling)
        model.togglePause()
        #expect(model.isPaused)
        #expect(!model.isSampling)
        model.togglePause()
        model.isWindowHidden = true
        #expect(!model.isSampling)
    }

    @Test func samplesThroughTheRepository() async {
        let repository = FakeContainerRepository([])
        let model = LiveStatsViewModel(containerID: "c1", repository: repository)
        await model.sampleOnce()
        #expect(repository.actions == ["stats c1"])
        #expect(model.points.count == 1)
    }

    @Test func rateFormatsShareTheLargerUnit() {
        #expect(RateFormat.pair(512, 20) == "512 B/s · 20 B/s")
        #expect(RateFormat.pair(42_000, 900) == "42 KB/s · 1 KB/s")
        #expect(RateFormat.pair(300_000, 1_200_000) == "0.3 MB/s · 1.2 MB/s")
    }
}

@Suite struct StatsValueFormatTests {
    @Test func axisAndReadoutLabels() {
        #expect(StatsValueFormat.percent(3.14) == "3.1%")
        #expect(StatsValueFormat.percent(50) == "50%")
        #expect(StatsValueFormat.bytes(0) == "0")
        #expect(StatsValueFormat.bytes(214 * 1_048_576) == "214 MiB")
        #expect(StatsValueFormat.bytes(1_610_612_736) == "1.5 GiB")
        #expect(StatsValueFormat.rate(0) == "0")
        #expect(StatsValueFormat.rate(500) == "500 B/s")
        #expect(StatsValueFormat.rate(42_000) == "42 KB/s")
        #expect(StatsValueFormat.rate(1_200_000) == "1.2 MB/s")
    }

    @MainActor
    @Test func hoverPicksTheNearestSample() {
        let model = LiveStatsViewModel(containerID: "c1", repository: FakeContainerRepository([]))
        for second in [0.0, 2, 4] {
            model.record(ContainerStats(cpuPercent: second, memoryBytes: 0, sampledAt: Date(timeIntervalSince1970: 1_000 + second)))
        }
        model.hoveredTime = Date(timeIntervalSince1970: 1_002.7)
        #expect(model.hoveredPoint?.cpu == 2)
        model.hoveredTime = nil
        #expect(model.hoveredPoint == nil)
    }
}
