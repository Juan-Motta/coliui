import AppKit
import ColiUICore
import SwiftUI

struct ContainersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var containers = model.containers
        let pendingRemoval = containers.pendingRemoval
        VStack(alignment: .leading, spacing: 14) {
            if containers.viewMode == .list {
                HStack {
                    Picker("Filter", selection: $containers.filter) {
                        ForEach(ContainerFilter.allCases) { filter in
                            Text("\(filter.rawValue) (\(containers.count(for: filter)))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Text("Updates every 3 s")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                content
            } else {
                ContentUnavailableView(
                    "Compose groups",
                    systemImage: "square.stack.3d.down.right",
                    description: Text("Designed, not built yet.")
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .navigationTitle("Containers")
        .navigationSubtitle("\(containers.runningCount) running · \(containers.stoppedCount) stopped")
        .searchable(text: $containers.searchText, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("View", selection: $containers.viewMode) {
                    ForEach(ContainerViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await containers.refresh() }
                }
                .keyboardShortcut("r")
                Menu("Sort", systemImage: "line.3.horizontal.decrease") {
                    Picker("Sort by", selection: $containers.sort) {
                        ForEach(ContainerSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            ToolbarItem {
                Button("Run container", systemImage: "plus") {}
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .disabled(true)
                    .help("Designed, not built yet")
            }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { containers.pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { container in
            Button("Remove", role: .destructive) {
                Task { await containers.perform(.remove, on: container) }
            }
        } message: { container in
            Text(container.isRunning ? "It's running and will be stopped first. This can't be undone." : "This can't be undone.")
        }
        .overlay(alignment: .bottom) {
            if let error = containers.errorMessage, !containers.containers.isEmpty {
                ErrorBanner(message: error) { containers.errorMessage = nil }
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let containers = model.containers
        if !containers.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if containers.containers.isEmpty, let error = containers.errorMessage {
            ContentUnavailableView {
                Label("Docker isn't reachable", systemImage: "shippingbox")
            } description: {
                Text(error)
            } actions: {
                Button("Start Colima") { Task { await model.performColima(.start) } }
                    .buttonStyle(.glassProminent)
                    .disabled(model.colima.isBusy)
            }
        } else if containers.visibleContainers.isEmpty {
            ContentUnavailableView(
                containers.containers.isEmpty ? "No containers" : "No matches",
                systemImage: "shippingbox",
                description: Text(containers.containers.isEmpty ? "Run one with `docker run`." : "Try another filter or search.")
            )
        } else {
            ContainersCard()
        }
    }
}

/// Proportional column widths shared by the header and every row.
private struct Columns {
    static let actions: CGFloat = 96
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20

    let name, image, status, ports, cpu, memory: CGFloat

    init(width: CGFloat) {
        let flexible = max(width - 2 * Self.padding - Self.actions - 6 * Self.spacing, 360)
        let unit = flexible / 9
        name = 2 * unit
        image = 2 * unit
        status = 1.5 * unit
        ports = 1.5 * unit
        cpu = 0.9 * unit
        memory = 1.1 * unit
    }
}

private struct ContainersCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let containers = model.containers
        let visible = containers.visibleContainers
        GeometryReader { geometry in
            let columns = Columns(width: geometry.size.width)
            ScrollView {
                VStack(spacing: 0) {
                    HeaderRow(columns: columns)
                    Divider()
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, container in
                        ContainerRow(container: container, stats: containers.stats[container.id], columns: columns)
                        if index < visible.count - 1 {
                            Divider().padding(.horizontal, Columns.padding)
                        }
                    }
                }
                .background(.background, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
                .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)
        }
    }
}

private struct HeaderRow: View {
    let columns: Columns

    var body: some View {
        HStack(spacing: Columns.spacing) {
            Text("NAME").frame(width: columns.name, alignment: .leading)
            Text("IMAGE").frame(width: columns.image, alignment: .leading)
            Text("STATUS").frame(width: columns.status, alignment: .leading)
            Text("PORTS").frame(width: columns.ports, alignment: .leading)
            Text("CPU").frame(width: columns.cpu, alignment: .leading)
            Text("MEMORY").frame(width: columns.memory, alignment: .leading)
            Text("ACTIONS").frame(width: Columns.actions, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Columns.padding)
        .frame(height: 44)
    }
}

private struct ContainerRow: View {
    let container: Container
    let stats: ContainerStats?
    let columns: Columns

    var body: some View {
        HStack(spacing: Columns.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name).fontWeight(.medium).lineLimit(1)
                Text(container.shortID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: columns.name, alignment: .leading)

            Text(container.image)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: columns.image, alignment: .leading)

            ContainerStatusLabel(container: container)
                .frame(width: columns.status, alignment: .leading)

            PortsLabel(container: container)
                .frame(width: columns.ports, alignment: .leading)

            Text(stats?.cpuDisplay ?? "—")
                .foregroundStyle(stats == nil ? .secondary : .primary)
                .frame(width: columns.cpu, alignment: .leading)

            Text(stats?.memoryDisplay ?? "—")
                .foregroundStyle(stats == nil ? .secondary : .primary)
                .frame(width: columns.memory, alignment: .leading)

            RowActions(container: container)
                .frame(width: Columns.actions, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, Columns.padding)
        .frame(height: 58)
        .contentShape(.rect)
        .contextMenu { ContainerMenu(container: container) }
    }
}

private struct PortsLabel: View {
    let container: Container

    var body: some View {
        if container.ports.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(container.ports.prefix(2), id: \.self) { port in
                    if let url = port.localURL {
                        Link(port.display, destination: url)
                    } else {
                        Text(port.display).foregroundStyle(.secondary)
                    }
                }
                if container.ports.count > 2 {
                    Text("+\(container.ports.count - 2)").foregroundStyle(.secondary)
                }
            }
            .font(.callout.monospaced())
            .lineLimit(1)
        }
    }
}

/// 28 pt circular hit target with a pressed highlight, matching the design's icon buttons.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.0), in: .circle)
            .contentShape(.circle)
    }
}

private struct RowActions: View {
    @Environment(AppModel.self) private var model
    let container: Container

    var body: some View {
        let containers = model.containers
        let isBusy = containers.busyIDs.contains(container.id)
        HStack(spacing: 4) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else if container.isRunning {
                Button("Stop", systemImage: "stop.fill") { Task { await containers.perform(.stop, on: container) } }
                    .foregroundStyle(.primary)
                    .help("Stop")
            } else {
                Button("Start", systemImage: "play.fill") { Task { await containers.perform(.start, on: container) } }
                    .foregroundStyle(.green)
                    .help("Start")
            }
            Button("Restart", systemImage: "arrow.clockwise") { Task { await containers.perform(.restart, on: container) } }
                .foregroundStyle(.primary)
                .help("Restart")
            Button("Remove", systemImage: "trash") { containers.pendingRemoval = container }
                .foregroundStyle(.red)
                .help("Remove…")
        }
        .buttonStyle(IconButtonStyle())
        .disabled(isBusy)
    }
}

private struct ContainerMenu: View {
    @Environment(AppModel.self) private var model
    let container: Container

    var body: some View {
        let containers = model.containers
        if let url = container.ports.lazy.compactMap(\.localURL).first {
            Button("Open \(url.host() ?? "localhost"):\(url.port ?? 0)") { NSWorkspace.shared.open(url) }
            Divider()
        }
        if container.isRunning {
            Button("Stop") { Task { await containers.perform(.stop, on: container) } }
        } else {
            Button("Start") { Task { await containers.perform(.start, on: container) } }
        }
        Button("Restart") { Task { await containers.perform(.restart, on: container) } }
        Divider()
        Button("Copy Container ID") { copy(container.id) }
        Button("Copy “docker exec -it \(container.shortID) sh”") { copy("docker exec -it \(container.shortID) sh") }
        Divider()
        Button("Remove…", role: .destructive) { containers.pendingRemoval = container }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).lineLimit(2)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}
