import AppKit
import ColiUICore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let colima = model.colima
        let containers = model.containers
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: Glyph.menuBarImage(dimmed: false, side: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ColiUI").font(.headline)
                    Text("Profile: \(colima.profile)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(title: colima.statusTitle, tint: colima.statusTint, isBusy: colima.isBusy)
            }

            if let instance = colima.instance {
                HStack(spacing: 8) {
                    MetricTile(title: "CPU", value: "\(instance.cpus) cores")
                    MetricTile(title: "Memory", value: instance.memoryDisplay)
                    MetricTile(title: "Disk", value: instance.diskDisplay)
                }
            }

            HStack {
                if colima.isRunning {
                    Button("Restart VM", systemImage: "arrow.clockwise") { Task { await model.performColima(.restart) } }
                        .frame(maxWidth: .infinity)
                    Button("Stop VM", systemImage: "stop.fill", role: .destructive) { Task { await model.performColima(.stop) } }
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Start VM", systemImage: "play.fill") { Task { await model.performColima(.start) } }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(colima.isBusy)

            if colima.isRunning {
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
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 320)
        .task { model.startPolling() }
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
