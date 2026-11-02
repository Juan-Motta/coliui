import AppKit
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
                        ChartCard(title: "CPU", detail: stats.cpuDetail, value: stats.cpuValue,
                                  series: [points.map(\.cpu)], range: stats.range, times: points.map(\.time))
                        ChartCard(title: "Memory", detail: stats.memoryDetail, value: stats.memoryValue,
                                  series: [points.map { Double($0.memory) }], range: stats.range, times: points.map(\.time))
                    }
                    GridRow {
                        ChartCard(title: "Network I/O", detail: "rx / tx", value: stats.networkValue,
                                  series: [points.map(\.received), points.map(\.sent)], legend: ("Received", "Sent"),
                                  range: stats.range, times: points.map(\.time))
                        ChartCard(title: "Block I/O", detail: "read / write", value: stats.blockValue,
                                  series: [points.map(\.read), points.map(\.written)], legend: ("Read", "Write"),
                                  range: stats.range, times: points.map(\.time))
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
    let title: String
    let detail: String
    let value: String
    /// One or two series; the first gets the area fill.
    let series: [[Double]]
    var legend: (String, String)?
    let range: StatsRange
    let times: [Date]

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

            LineChart(series: series, times: times, window: range.seconds)
                .frame(height: 120)
                .accessibilityElement()
                .accessibilityLabel("\(title) over the last \(range.rawValue), currently \(value)")

            if let legend {
                HStack(spacing: 16) {
                    LegendKey(color: Palette.accent, title: legend.0)
                    LegendKey(color: Palette.diskCache, title: legend.1)
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

/// Gridlines at quarters, a 2 pt blue line with a 10% area, an orange second line.
/// The right edge is the newest sample, so a fresh chart fills in from the right.
private struct LineChart: View {
    let series: [[Double]]
    let times: [Date]
    let window: TimeInterval

    var body: some View {
        Canvas { context, size in
            for fraction in [0.25, 0.5, 0.75] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(grid, with: .color(Palette.chartGrid), lineWidth: 1)
            }
            guard let end = times.last, times.count > 1 else { return }
            // Headroom above the peak; a flat zero line sits on the bottom edge.
            let peak = max(series.flatMap { $0 }.max() ?? 0, 0) * 1.25
            let top = peak > 0 ? peak : 1
            func point(_ index: Int, _ value: Double) -> CGPoint {
                let age = end.timeIntervalSince(times[index])
                return CGPoint(x: size.width * (1 - age / window), y: size.height * (1 - value / top))
            }
            for (number, values) in series.enumerated() {
                var line = Path()
                for (index, value) in values.enumerated() {
                    index == 0 ? line.move(to: point(index, value)) : line.addLine(to: point(index, value))
                }
                if number == 0 {
                    var area = line
                    area.addLine(to: CGPoint(x: point(values.count - 1, 0).x, y: size.height))
                    area.addLine(to: CGPoint(x: point(0, 0).x, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .color(Palette.accent.opacity(0.10)))
                }
                context.stroke(line, with: .color(number == 0 ? Palette.accent : Palette.diskCache),
                               style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
    }
}
