import AppKit
import ColiUICore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    @State private var pendingConfirmation: MenuConfirmation?

    var body: some View {
        let colima = model.colima
        let containers = model.containers
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: Glyph.menuBarImage(dimmed: false, side: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ColiUI").font(.headline)
                    Text(verbatim: model.usesColima ? "Profile: \(colima.profile)" : model.engineKind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.usesColima {
                    StatusBadge(title: model.isEngineRunning ? "Running" : "Not running",
                                tint: model.isEngineRunning ? .green : .gray, isBusy: false)
                }
                Button { pendingConfirmation = .quit } label: {
                    Image(systemName: "xmark")
                }
                .help("Quit ColiUI")
                .keyboardShortcut("q")
                .buttonStyle(.glass)
                .padding(.leading, 5)
            }

            if !model.usesColima {
                if let info = model.engineInfo {
                    HStack(spacing: 8) {
                        MetricTile(title: "CPU", value: "\(info.cpus) cores")
                        MetricTile(title: "Memory", value: info.memoryText)
                        MetricTile(title: "Disk", value: model.cleanup.usage.map { "\(ByteFormat.binary($0.totalBytes)) used" } ?? "—")
                    }
                }
                if model.engineApp != nil {
                    Button("Open \(model.engineKind.displayName)") { model.openEngineApp() }
                        .frame(maxWidth: .infinity)
                }
            }

            if let offer = model.updates.offer {
                UpdateBanner(version: offer.version) {
                    openWindow(id: "main")
                    NSApp.activate()
                    model.viewUpdate()
                }
            }

            if model.usesColima {
                HStack {
                    if colima.isRunning {
                        Button { pendingConfirmation = .restart } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Restart Colima")
                        Button { pendingConfirmation = .stop } label: {
                            Image(systemName: "stop.fill")
                        }
                        .help("Stop Colima")
                    } else {
                        Button { Task { await model.performColima(.start) } } label: {
                            Image(systemName: "play.fill")
                        }
                        .tint(.blue)
                        .help("Start Colima")
                    }
                    Spacer()
                    StatusBadge(title: colima.statusTitle,
                                tint: colima.isRunning ? colima.statusTint : .red,
                                isBusy: colima.isBusy)
                }
                .buttonStyle(.borderless)
                .disabled(colima.isBusy)
            }

            if model.usesColima, colima.isRunning, let instance = colima.instance {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ResourceCard(title: "CPU", resource: "\(instance.cpus) cores",
                                     usage: colima.resourceUsage?.cpuDisplay ?? "—",
                                     level: (colima.resourceUsage?.cpuPercent ?? 0) / 100, history: cpuHistory)
                        ResourceCard(title: "RAM", resource: instance.memoryDisplay,
                                     usage: colima.resourceUsage.map { ByteFormat.binary($0.memoryUsedBytes) } ?? "—",
                                     level: colima.resourceUsage.map { Double($0.memoryUsedBytes) / Double(max($0.memoryTotalBytes, 1)) } ?? 0,
                                     history: memoryHistory)
                    }
                    let disk = colima.resourceUsage
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("DISK").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text(disk.map { "\(ByteFormat.binary($0.diskUsedBytes)) / \(ByteFormat.binary($0.diskTotalBytes))" } ?? "—")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        GeometryReader { geometry in
                            Capsule().fill(.quaternary)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.green.gradient)
                                        .frame(width: geometry.size.width * min(max(disk.map { Double($0.diskUsedBytes) / Double(max($0.diskTotalBytes, 1)) } ?? 0, 0), 1))
                                }
                        }
                        .frame(height: 6)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
                }
            }

            if model.isEngineRunning {
                HStack {
                    Text("CONTAINERS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(containers.runningCount) of \(containers.containers.count) running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    ForEach(containers.containers.prefix(8)) { container in
                        MenuBarContainerRow(container: container)
                    }
                }
                if containers.containers.isEmpty {
                    Text("No containers").font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Open ColiUI") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.glass)
                Spacer()
                if model.updates.canUpdate {
                    Button("Check for Updates…") {
                        openWindow(id: "main")
                        NSApp.activate()
                        model.checkForUpdatesFromMenu()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .overlay {
            if let pendingConfirmation {
                ZStack {
                    Color.black.opacity(0.62)
                    VStack(spacing: 12) {
                        Text(pendingConfirmation.title).font(.headline)
                        Text(pendingConfirmation.message)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        HStack {
                            Button("Cancel") { self.pendingConfirmation = nil }
                                .keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Confirm", role: .destructive) {
                                confirm(pendingConfirmation, model: model)
                                self.pendingConfirmation = nil
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 260)
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
                .ignoresSafeArea()
            }
        }
        .task {
            model.startPolling()
            while !Task.isCancelled {
                await colima.refreshResourceUsage()
                if let usage = colima.resourceUsage {
                    cpuHistory.append(usage.cpuPercent / 100)
                    memoryHistory.append(Double(usage.memoryUsedBytes) / Double(max(usage.memoryTotalBytes, 1)))
                    cpuHistory = Array(cpuHistory.suffix(24))
                    memoryHistory = Array(memoryHistory.suffix(24))
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func confirm(_ action: MenuConfirmation, model: AppModel) {
        switch action {
        case .restart: Task { await model.performColima(.restart) }
        case .stop: Task { await model.performColima(.stop) }
        case .quit: NSApp.terminate(nil)
        }
    }
}

private enum MenuConfirmation {
    case restart, stop, quit
    var title: String {
        switch self {
        case .restart: "Restart Colima?"
        case .stop: "Stop Colima?"
        case .quit: "Quit ColiUI?"
        }
    }
    var message: String {
        switch self {
        case .restart: "This will restart the Colima VM."
        case .stop: "Containers and services running in Colima will stop."
        case .quit: "ColiUI will close. Your containers will keep running."
        }
    }
}

private struct ResourceCard: View {
    let title: String
    let resource: String
    let usage: String
    let level: Double
    let history: [Double]

    private var tint: Color {
        Color(hue: 0.33 * (1 - min(max(level, 0), 1)), saturation: 0.78, brightness: 0.82)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(resource).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(usage).font(.callout.weight(.semibold).monospacedDigit())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(10)
        .background {
            GeometryReader { proxy in
                if history.count > 1 {
                    UsageArea(values: history)
                        .fill(LinearGradient(colors: [tint.opacity(0.02), tint.opacity(0.42)], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .bottom) {
                            UsageSparkline(values: history)
                                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct UsageArea: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let line = UsageSparkline(values: values).path(in: rect)
        var area = line
        area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        area.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        area.closeSubpath()
        return area
    }
}

private struct UsageSparkline: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let points = values.enumerated().map { index, value in
            CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.maxY - rect.height * CGFloat(min(max(value, 0), 1)))
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = (previous.x + current.x) / 2
            path.addQuadCurve(to: CGPoint(x: midpoint, y: (previous.y + current.y) / 2), control: previous)
            path.addQuadCurve(to: current, control: current)
        }
        return path
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

private struct MenuBarContainerRow: View {
    @Environment(AppModel.self) private var model
    let container: Container

    var body: some View {
        let containers = model.containers
        HStack(spacing: 10) {
            Circle().fill(container.statusTint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(container.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if containers.busyIDs.contains(container.id) {
                ProgressView().controlSize(.small)
            } else if container.isRunning {
                Button("Stop", systemImage: "stop.fill") { Task { await containers.perform(.stop, on: container) } }
            } else {
                Button("Start", systemImage: "play.fill") { Task { await containers.perform(.start, on: container) } }
                    .tint(.green)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
