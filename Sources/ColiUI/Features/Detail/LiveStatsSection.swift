import AppKit
import Charts
import SwiftUI

/// LiveStats.dc.html: range segments, sampling note, Pause, then four chart cards in two columns.
struct LiveStatsSection: View {
    let stats: LiveStatsViewModel

    var body: some View {
        @Bindable var stats = stats
        let points = stats.visiblePoints
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    RangeSegments(selection: $stats.range)
                    HStack(spacing: 6) {
                        Circle().fill(stats.isSampling ? Palette.greenDot : Palette.grayDot).frame(width: 7, height: 7)
                        Text(stats.errorMessage ?? (stats.isPaused ? "Paused" : "Sampling every 2 s · paused when the window is hidden"))
                            .lineLimit(1)
                    }
                    .font(.ui(12))
                    .foregroundStyle(stats.errorMessage == nil ? Palette.secondary : Palette.danger)
                    Spacer()
                    Button(stats.isPaused ? "Resume" : "Pause") { stats.togglePause() }
                        .buttonStyle(PillButtonStyle())
                        .help(stats.isPaused ? "Resume sampling" : "Stop sampling; the charts keep what they have")
                }

                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        ChartCard(stats: stats, title: "CPU", detail: stats.cpuDetail, value: stats.cpuValue,
                                  series: [("CPU", \.cpu)], format: StatsValueFormat.percent)
                        ChartCard(stats: stats, title: "Memory", detail: stats.memoryDetail, value: stats.memoryValue,
                                  series: [("Memory", { Double($0.memory) })], format: StatsValueFormat.bytes)
                    }
                    GridRow {
                        ChartCard(stats: stats, title: "Network I/O", detail: "rx / tx", value: stats.networkValue,
                                  series: [("Received", \.received), ("Sent", \.sent)], format: StatsValueFormat.rate)
                        ChartCard(stats: stats, title: "Block I/O", detail: "read / write", value: stats.blockValue,
                                  series: [("Read", \.read), ("Write", \.written)], format: StatsValueFormat.rate)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeOcclusionStateNotification)) { _ in
            stats.isWindowHidden = !NSApp.occlusionState.contains(.visible)
        }
    }
}

/// Plain field capsule (not glass) holding `.seg` buttons.
private struct RangeSegments: View {
    @Binding var selection: StatsRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatsRange.allCases) { range in
                let isOn = range == selection
                Button { selection = range } label: {
                    Hoverable { hovered in
                        Text(range.rawValue)
                            .font(.ui(12, isOn ? .semibold : .regular))
                            .foregroundStyle(isOn || hovered ? Palette.segmentOnText : Palette.segmentOffText)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background {
                                if isOn { Capsule().fill(Palette.segmentOn).shadow(color: .black.opacity(0.14), radius: 2, y: 1) }
                            }
                            .contentShape(.capsule)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 34)
        .background(Palette.field, in: .capsule)
    }
}

private struct ChartCard: View {
    let stats: LiveStatsViewModel
    let title: String
    let detail: String
    let value: String
    /// One or two series; the first is blue with the area fill, the second orange.
    let series: [(name: String, value: (StatsPoint) -> Double)]
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(detail)
            }
            .font(.ui(12))
            .foregroundStyle(Palette.secondary)

            Text(verbatim: value)
                .font(.ui(24, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            StatsChart(stats: stats, series: series, format: format)
                .frame(height: 120)
                .accessibilityLabel("\(title) over the last \(stats.range.rawValue), currently \(value)")

            if series.count > 1 {
                HStack(spacing: 16) {
                    LegendKey(color: Palette.accent, title: series[0].name)
                    LegendKey(color: Palette.diskCache, title: series[1].name)
                }
                .font(.ui(12))
                .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }
}

private struct LegendKey: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            color.frame(width: 12, height: 2)
            Text(title)
        }
    }
}

/// Values on the leading axis, clock time below, and a shared hover rule with the exact reading.
private struct StatsChart: View {
    let stats: LiveStatsViewModel
    let series: [(name: String, value: (StatsPoint) -> Double)]
    let format: (Double) -> String

    var body: some View {
        @Bindable var stats = stats
        let points = stats.visiblePoints
        let end = points.last?.time ?? Date()
        let start = end.addingTimeInterval(-stats.range.seconds)
        let peak = points.flatMap { point in series.map { $0.value(point) } }.max() ?? 0
        let top = peak > 0 ? peak * 1.25 : 1
        let hovered = stats.hoveredPoint
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { number, line in
                let color = number == 0 ? Palette.accent : Palette.diskCache
                ForEach(points, id: \.time) { point in
                    if number == 0 {
                        AreaMark(x: .value("Time", point.time), y: .value(line.name, line.value(point)))
                            .foregroundStyle(Palette.accent.opacity(0.10))
                            .interpolationMethod(.linear)
                    }
                    LineMark(x: .value("Time", point.time), y: .value(line.name, line.value(point)), series: .value("Series", line.name))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
            if let hovered {
                RuleMark(x: .value("Time", hovered.time))
                    .foregroundStyle(Palette.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverReadout(time: hovered.time, readings: series.map { ($0.name, format($0.value(hovered))) },
                                     showSeconds: true)
                    }
                ForEach(Array(series.enumerated()), id: \.offset) { number, line in
                    PointMark(x: .value("Time", hovered.time), y: .value(line.name, line.value(hovered)))
                        .foregroundStyle(number == 0 ? Palette.accent : Palette.diskCache)
                        .symbolSize(28)
                }
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Palette.chartGrid)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: stats.range == .oneMinute
                             ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
                    }
                }
                .font(.ui(10))
                .foregroundStyle(Palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Palette.chartGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(verbatim: format(number)) }
                }
                .font(.ui(10))
                .foregroundStyle(Palette.secondary)
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $stats.hoveredTime)
    }
}

/// Small card above the hover rule: the sample's time and each series' value.
private struct HoverReadout: View {
    let time: Date
    let readings: [(String, String)]
    let showSeconds: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time, format: .dateTime.hour().minute().second())
                .font(.ui(10))
                .foregroundStyle(Palette.secondary)
            ForEach(readings, id: \.0) { name, value in
                Text(verbatim: readings.count > 1 ? "\(name) \(value)" : value)
                    .font(.ui(11, .semibold))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Palette.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
