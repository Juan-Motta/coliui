import AppKit
import ColiUICore
import SwiftUI

/// Main.dc.html: header (60 pt), filter row, then the containers card.
struct ContainersView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var containers = model.containers
        let pendingRemoval = containers.pendingRemoval
        VStack(alignment: .leading, spacing: 0) {
            Header()
            VStack(alignment: .leading, spacing: 14) {
                if containers.viewMode == .list {
                    HStack {
                        CapsuleSegmented(
                            options: ContainerFilter.allCases.map {
                                SegmentOption(value: $0, title: "\($0.rawValue) (\(containers.count(for: $0)))")
                            },
                            selection: $containers.filter
                        )
                        Spacer()
                        Text("Live via Docker events")
                            .font(.ui(12))
                            .foregroundStyle(Palette.secondary)
                    }
                    content
                } else {
                    // Computed once per render and handed down (grouping sorts twice).
                    let groups = containers.composeGroups
                    if groups.isEmpty { content } else { ComposeGroupsView(groups: groups) }
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            // ↑/↓ move the selection, Space starts or stops it (Settings › Shortcuts).
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.downArrow) { containers.selectNext(); return .handled }
            .onKeyPress(.upArrow) { containers.selectPrevious(); return .handled }
            .onKeyPress(.space) {
                guard containers.selectedContainer != nil else { return .ignored }
                Task { await containers.toggleSelected() }
                return .handled
            }
            .onAppear { listFocused = true }
        }
        .background { SelectionShortcuts() }
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
        .sheet(isPresented: Binding(get: { model.runForm != nil }, set: { if !$0 { model.closeRunForm() } })) {
            if let form = model.runForm {
                RunContainerSheet(form: form).environment(model)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = containers.errorMessage, !containers.containers.isEmpty {
                ErrorBanner(message: error) { containers.errorMessage = nil }
                    .padding(.bottom, 16)
            } else if let toast = containers.toast {
                ToastView(message: toast).padding(.bottom, 20)
            }
        }
        .animation(.easeOut(duration: 0.2), value: containers.toast)
    }

    @ViewBuilder
    private var content: some View {
        let containers = model.containers
        let visible = containers.visibleContainers
        if !containers.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if containers.containers.isEmpty, let error = containers.errorMessage {
            ContentUnavailableView {
                Label("Docker isn't reachable", systemImage: "shippingbox")
            } description: {
                Text(error)
            } actions: {
                Button { Task { await model.performColima(.start) } } label: { Text("Start Colima") }
                    .buttonStyle(TintButtonStyle())
                    .disabled(model.colima.isBusy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            ContentUnavailableView(
                containers.containers.isEmpty ? "No containers" : "No matches",
                systemImage: "shippingbox",
                description: Text(containers.containers.isEmpty ? "Run one with `docker run`." : "Try another filter or search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContainersCard(visible: visible)
        }
    }
}

/// ⌘L, ⌘O and ⌘⌫ for the selected container; invisible buttons so the shortcuts work without a menu.
private struct SelectionShortcuts: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let containers = model.containers
        let selected = containers.selectedContainer
        Group {
            Button("View Logs") { if let selected { model.openDetail(selected) } }
                .keyboardShortcut("l")
            Button("Open Port in Browser") { if let url = containers.selectedPortURL { NSWorkspace.shared.open(url) } }
                .keyboardShortcut("o")
            Button("Remove Selected") { containers.requestRemoveSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                // In the Search field ⌘⌫ deletes the text; it must not ask to remove the container.
                .disabled(containers.isSearchFocused)
            Button("Open Shell") { if let selected { model.openDetail(selected, tab: .terminal) } }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(selected?.isRunning != true)
        }
        .disabled(selected == nil)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Title + subtitle, view toggle, spacer, refresh/sort capsule, search capsule, Run container.
private struct Header: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var containers = model.containers
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Containers").font(.ui(15, .semibold))
                Text("\(containers.runningCount) running · \(containers.stoppedCount) stopped")
                    .font(.ui(11))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.trailing, 6)

            CapsuleSegmented(
                options: [
                    SegmentOption(value: .list, title: ContainerViewMode.list.rawValue, help: "Show all containers in one list"),
                    SegmentOption(value: .compose, title: ContainerViewMode.compose.rawValue, help: "Group containers by Compose project"),
                ],
                selection: $containers.viewMode
            )

            Spacer(minLength: 10)

            GlassCapsule {
                Button { Task { await containers.refresh() } } label: {
                    Label { Text("Refresh") } icon: { LineIcon(kind: .refresh).icon(Palette.text, size: 16) }
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")

                Menu {
                    Picker("Sort by", selection: $containers.sort) {
                        ForEach(ContainerSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Hoverable { hovered in
                        LineIcon(kind: .sort).icon(Palette.text, size: 16)
                            .frame(width: 34, height: 28)
                            .background(hovered ? Palette.hover : .clear, in: .capsule)
                            .contentShape(.capsule)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort by name or status")
                .accessibilityLabel("Sort")
            }

            HStack(spacing: 6) {
                LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                TextField("Search", text: $containers.searchText)
                    .textFieldStyle(.plain)
                    .font(.ui(13))
                    .focused($searchFocused)
                    .onChange(of: searchFocused) { containers.isSearchFocused = searchFocused }
            }
            .background {
                Button("Search") { searchFocused = true }
                    .keyboardShortcut("f")
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(width: 200, height: 34)
            .glassSurface(Capsule())
            .help("Search by name or image (⌘F)")

            Button { model.openRunForm() } label: {
                HStack(spacing: 6) {
                    LineIcon(kind: .plus).icon(.white, size: 14, svgStrokeWidth: 2.4)
                    Text("Run container")
                }
            }
            .buttonStyle(TintButtonStyle())
            .keyboardShortcut("n")
            .help("Run a new container (⌘N)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }
}

/// `grid-template-columns: 2fr 2fr 1.4fr 1.4fr 0.8fr 1fr 112px; gap: 12px; padding: 0 16px`.
private struct Columns {
    static let actions: CGFloat = 112
    static let gap: CGFloat = 12
    static let padding: CGFloat = 16

    let name, image, status, ports, cpu, memory: CGFloat

    init(width: CGFloat) {
        let fractions = max(width - 2 * Self.padding - Self.actions - 6 * Self.gap, 0)
        let fr = fractions / 8.6
        name = 2 * fr
        image = 2 * fr
        status = 1.4 * fr
        ports = 1.4 * fr
        cpu = 0.8 * fr
        memory = 1 * fr
    }
}

private struct ContainersCard: View {
    @Environment(AppModel.self) private var model
    let visible: [Container]

    var body: some View {
        let containers = model.containers
        // The window's minimum width keeps the card at ≥ 760 pt, so only vertical scrolling is needed;
        // a two-axis ScrollView would centre a short card vertically.
        GeometryReader { geometry in
            let columns = Columns(width: geometry.size.width)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    HeaderRow(columns: columns)
                    ForEach(visible) { container in
                        ContainerRow(container: container, stats: containers.stats[container.id], columns: columns)
                    }
                }
                .frame(width: geometry.size.width)
                .background(Palette.card)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .defaultScrollAnchor(.top)
            .scrollIndicators(.automatic)
        }
    }
}

private struct HeaderRow: View {
    let columns: Columns

    var body: some View {
        HStack(spacing: Columns.gap) {
            Text("NAME").frame(width: columns.name, alignment: .leading)
            Text("IMAGE").frame(width: columns.image, alignment: .leading)
            Text("STATUS").frame(width: columns.status, alignment: .leading)
            Text("PORTS").frame(width: columns.ports, alignment: .leading)
            Text("CPU").frame(width: columns.cpu, alignment: .leading)
            Text("MEMORY").frame(width: columns.memory, alignment: .leading)
            // Centred over the button group: each icon sits in a 28 pt hit area, so trailing alignment drifts.
            Text("ACTIONS").frame(width: Columns.actions, alignment: .center)
        }
        .font(.ui(11, .semibold))
        .tracking(0.33)
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, Columns.padding)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }
    }
}

private struct ContainerRow: View {
    @Environment(AppModel.self) private var model
    let container: Container
    let stats: ContainerStats?
    let columns: Columns

    var body: some View {
        let containers = model.containers
        HStack(spacing: Columns.gap) {
            VStack(alignment: .leading, spacing: 0) {
                Text(container.name).font(.ui(13, .medium)).foregroundStyle(Palette.text).lineLimit(1)
                Text(container.shortID).font(.mono(11)).foregroundStyle(Palette.secondary)
            }
            .frame(width: columns.name, alignment: .leading)

            Text(container.image)
                .font(.mono(12))
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columns.image, alignment: .leading)

            ContainerStatusLabel(container: container)
                .frame(width: columns.status, alignment: .leading)

            PortsLabel(container: container)
                .frame(width: columns.ports, alignment: .leading)

            Text(stats?.cpuDisplay ?? "—")
                .font(.ui(12))
                .foregroundStyle(Palette.tertiary)
                .frame(width: columns.cpu, alignment: .leading)

            Text(stats?.memoryDisplay ?? "—")
                .font(.ui(12))
                .foregroundStyle(Palette.tertiary)
                .frame(width: columns.memory, alignment: .leading)

            RowActions(container: container)
                .frame(width: Columns.actions, alignment: .center)
        }
        .padding(.horizontal, Columns.padding)
        .frame(height: 52)
        .rowWash(isSelected: containers.selectedID == container.id)
        .overlay(alignment: .bottom) { Palette.rowDivider.frame(height: 1) }
        .contentShape(.rect)
        // The whole row opens the detail; the port link and the buttons keep their own clicks.
        .onTapGesture {
            containers.selectedID = container.id
            model.openDetail(container)
        }
        .help("Show logs and details of \(container.name)")
        .contextMenu { ContainerMenu(container: container) }
    }
}

private struct PortsLabel: View {
    let container: Container

    var body: some View {
        Group {
            if container.ports.isEmpty {
                Text("—")
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(container.ports.enumerated()), id: \.element) { index, port in
                        let text = port.publicPort.map { "\($0)→\(port.privatePort)" } ?? "\(port.privatePort)"
                        if let url = port.localURL {
                            PortLink(title: text, url: url)
                        } else {
                            Text(text)
                        }
                        if index < container.ports.count - 1 { Text(", ") }
                    }
                }
            }
        }
        .font(.mono(12))
        .foregroundStyle(Palette.accent)
        .tint(Palette.accent)
        .lineLimit(1)
    }
}

/// `M8 5v14l11-7z`
struct PlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: 8 * s, y: 5 * s))
        path.addLine(to: CGPoint(x: 8 * s, y: 19 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct RowActions: View {
    @Environment(AppModel.self) private var model
    let container: Container

    var body: some View {
        let containers = model.containers
        let isBusy = containers.busyIDs.contains(container.id)
        HStack(spacing: 2) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else if container.isRunning {
                Button { Task { await containers.perform(.stop, on: container) } } label: {
                    Label {
                        Text("Stop")
                    } icon: {
                        // rect x6 y6 12×12 rx2 in a 24 box at 14 pt
                        RoundedRectangle(cornerRadius: 14 / 12).fill(Palette.text).frame(width: 7, height: 7).frame(width: 14, height: 14)
                    }
                }
                .help("Stop \(container.name)")
            } else {
                Button { Task { await containers.perform(.start, on: container) } } label: {
                    Label { Text("Start") } icon: { PlayShape().fill(Palette.greenText).frame(width: 14, height: 14) }
                }
                .help("Start \(container.name)")
            }
            Button { Task { await containers.perform(.restart, on: container) } } label: {
                Label { Text("Restart") } icon: { LineIcon(kind: .refresh).icon(Palette.text, size: 14, svgStrokeWidth: 2.2) }
            }
            .help("Restart \(container.name)")
            Button { containers.pendingRemoval = container } label: {
                Label { Text("Remove") } icon: { LineIcon(kind: .trash).icon(Palette.danger, size: 14) }
            }
            .help("Remove \(container.name)…")
        }
        .buttonStyle(ToolbarIconButtonStyle(width: 28))
        .disabled(isBusy)
    }
}

struct ContainerMenu: View {
    @Environment(AppModel.self) private var model
    let container: Container

    var body: some View {
        let containers = model.containers
        Button("Show Logs and Details") { model.openDetail(container) }
        Divider()
        if let url = container.ports.lazy.compactMap(\.localURL).first {
            Button { NSWorkspace.shared.open(url) } label: {
                Text(verbatim: "Open \(url.host() ?? "localhost"):\(url.port ?? 0)")
            }
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

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orangeDot)
            Text(message).lineLimit(2)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.ui(12))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(Capsule())
    }
}
