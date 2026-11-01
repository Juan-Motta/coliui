import AppKit
import ColiUICore
import SwiftUI

struct ContainersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var containers = model.containers
        let pendingRemoval = containers.pendingRemoval
        content
            .navigationTitle("Containers")
            .navigationSubtitle("\(containers.runningCount) running · \(containers.stoppedCount) stopped")
            .searchable(text: $containers.searchText, placement: .toolbar, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $containers.filter) {
                        ForEach(ContainerFilter.allCases) { filter in
                            Text("\(filter.rawValue) (\(containers.count(for: filter)))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await containers.refresh() }
                    }
                    .keyboardShortcut("r")
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
            ProgressView()
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
            table
        }
    }

    private var table: some View {
        @Bindable var containers = model.containers
        return Table(containers.visibleContainers, selection: $containers.selection) {
            TableColumn("Name") { container in
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name).fontWeight(.medium)
                    Text(container.shortID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Image") { container in
                Text(container.image).font(.callout.monospaced()).lineLimit(1)
            }
            TableColumn("Status") { container in
                ContainerStatusLabel(container: container)
            }
            TableColumn("Ports") { container in
                PortsLabel(container: container)
            }
            TableColumn("") { container in
                RowActions(container: container) { containers.pendingRemoval = container }
            }
            .width(min: 100, ideal: 110, max: 120)
        }
        .contextMenu(forSelectionType: Container.ID.self) { ids in
            if let id = ids.first, let container = containers.containers.first(where: { $0.id == id }) {
                ContainerMenu(container: container) { containers.pendingRemoval = container }
            }
        }
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
        }
    }
}

private struct RowActions: View {
    @Environment(AppModel.self) private var model
    let container: Container
    let onRemove: () -> Void

    var body: some View {
        let containers = model.containers
        HStack(spacing: 2) {
            if containers.busyIDs.contains(container.id) {
                ProgressView().controlSize(.small).frame(width: 28)
            } else if container.isRunning {
                Button("Stop", systemImage: "stop.fill") { Task { await containers.perform(.stop, on: container) } }
            } else {
                Button("Start", systemImage: "play.fill") { Task { await containers.perform(.start, on: container) } }
                    .tint(.green)
            }
            Button("Restart", systemImage: "arrow.clockwise") { Task { await containers.perform(.restart, on: container) } }
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                .tint(.red)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(containers.busyIDs.contains(container.id))
    }
}

private struct ContainerMenu: View {
    @Environment(AppModel.self) private var model
    let container: Container
    let onRemove: () -> Void

    var body: some View {
        let containers = model.containers
        if let url = container.ports.lazy.compactMap(\.localURL).first {
            Button("Open \(url.host() ?? "localhost"):\(url.port ?? 0)") { NSWorkspace.shared.open(url) }
                .keyboardShortcut("o")
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
        Button("Remove…", role: .destructive, action: onRemove)
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
