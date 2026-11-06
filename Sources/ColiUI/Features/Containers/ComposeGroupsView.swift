import AppKit
import ColiUICore
import SwiftUI

/// Compose.dc.html: one card per Compose project, standalone containers last.
struct ComposeGroupsView: View {
    @Environment(AppModel.self) private var model

    let groups: [ComposeGroup]

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    ForEach(groups) { group in
                        GroupCard(group: group, columns: GroupColumns(width: geometry.size.width))
                    }
                }
                .frame(width: geometry.size.width)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.bottom, 16)
            }
            .defaultScrollAnchor(.top)
        }
    }
}

/// `grid-template-columns: 24px 1.6fr 1.8fr 1.4fr 1.6fr 76px; gap: 12px; padding: 0 12px 0 44px`.
private struct GroupColumns {
    static let dot: CGFloat = 24
    static let actions: CGFloat = 76
    static let gap: CGFloat = 12
    static let leading: CGFloat = 44
    static let trailing: CGFloat = 12

    let name, image, status, port: CGFloat

    init(width: CGFloat) {
        let fractions = max(width - Self.leading - Self.trailing - Self.dot - Self.actions - 5 * Self.gap, 0)
        let fr = fractions / 6.4
        name = 1.6 * fr
        image = 1.8 * fr
        status = 1.4 * fr
        port = 1.6 * fr
    }
}

private struct GroupCard: View {
    @Environment(AppModel.self) private var model
    let group: ComposeGroup
    let columns: GroupColumns

    var body: some View {
        let containers = model.containers
        let isOpen = !containers.collapsedGroups.contains(group.id)
        VStack(spacing: 0) {
            GroupHeader(group: group, isOpen: isOpen)
            if isOpen {
                ForEach(group.containers) { container in
                    ServiceRow(container: container, columns: columns)
                }
            }
        }
        .cardSurface()
        .clipShape(.rect(cornerRadius: 14))
    }
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: ComposeGroup
    let isOpen: Bool

    var body: some View {
        let containers = model.containers
        let running = group.runningCount
        let total = group.containers.count
        HStack(spacing: 10) {
            Button { containers.toggleGroup(group.id) } label: {
                Label {
                    Text(isOpen ? "Collapse" : "Expand")
                } icon: {
                    LineIcon(kind: .chevronRight).icon(Palette.text, size: 14, svgStrokeWidth: 2.4)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .buttonStyle(ToolbarIconButtonStyle(width: 28))
            .help(isOpen ? "Collapse \(group.name)" : "Expand \(group.name)")

            LineIcon(kind: .folder).icon(Palette.accent, size: 18)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(group.name).font(.ui(14, .semibold))
                    if !group.isStandalone {
                        FavoriteStar(isOn: model.favorites.isFavorite(project: group.name), size: 16,
                                     label: group.name) { model.toggleFavorite(project: group.name) }
                    }
                }
                Text(group.configFile.map(abbreviate) ?? "not part of a Compose project")
                    .font(.mono(11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(verbatim: "\(running) / \(total) running")
                .font(.ui(12, .semibold))
                .foregroundStyle(running == 0 ? Palette.secondary : running < total ? Palette.orangeText : Palette.greenText)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(running == 0 ? Palette.field : running < total ? Palette.orangePill : Palette.greenPill, in: .capsule)

            Spacer(minLength: 8)

            let groupStats = group.containers.filter(\.isRunning).compactMap { containers.stats[$0.id] }
            let cpu = groupStats.reduce(0.0) { $0 + $1.cpuPercent }
            let memory = groupStats.reduce(Int64(0)) { $0 + $1.memoryBytes }
            HStack(spacing: 12) {
                resourceStat("CPU", value: groupStats.isEmpty ? "—" : String(format: "%.1f%%", cpu))
                resourceStat("MEM", value: groupStats.isEmpty ? "—" : ByteFormat.binary(memory))
            }
            .padding(.trailing, 4)

            if running > 0 {
                groupAction("Stop all", icon: "stop.fill", help: "Stop the running containers of \\(group.name)", color: Palette.text) {
                    Task { await containers.perform(.stopAll, on: group) }
                }
            } else {
                groupAction("Start all", icon: "play.fill", help: "Start every container of \\(group.name)", color: Palette.greenText) {
                    Task { await containers.perform(.startAll, on: group) }
                }
            }
            groupAction("Restart", icon: "arrow.clockwise", help: "Restart every container of \\(group.name)") {
                Task { await containers.perform(.restart, on: group) }
            }
            if let file = group.configFile {
                groupAction("Edit compose file", icon: "pencil", help: "Open \\(abbreviate(file)) in your editor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: file))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func resourceStat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.ui(9, .semibold)).foregroundStyle(Palette.secondary)
            Text(value).font(.mono(11, .medium)).foregroundStyle(Palette.text).lineLimit(1)
        }
        .fixedSize()
    }

    private func groupAction(_ label: String, icon: String, help: String, color: Color = Palette.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Palette.field, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct ServiceRow: View {
    @Environment(AppModel.self) private var model
    let container: Container
    let columns: GroupColumns

    var body: some View {
        let containers = model.containers
        let command = "docker exec -it \(container.shortID) sh"
        let favorites = model.favorites
        let byProject = container.composeProject.map(favorites.isFavorite(project:)) == true
        HStack(spacing: GroupColumns.gap) {
            // Favorites.dc.html: the star sits in the row's leading gutter.
            FavoriteStar(isOn: favorites.contains(container), size: 15, label: container.name,
                         disabledHelp: byProject ? "Starred with \(container.composeProject ?? "")" : nil) {
                model.toggleFavorite(container)
            }
            .disabled(byProject)
            Circle().fill(container.statusTint).frame(width: 8, height: 8)
                .frame(width: GroupColumns.dot, alignment: .leading)

            Text(container.composeService ?? container.name)
                .font(.ui(13, .medium))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .frame(width: columns.name, alignment: .leading)

            Text(container.image)
                .font(.mono(12))
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
                .frame(width: columns.image, alignment: .leading)

            Text(container.status)
                .font(.ui(12))
                .foregroundStyle(container.statusTextColor)
                .lineLimit(1)
                .frame(width: columns.status, alignment: .leading)

            Group {
                if let port = container.ports.first(where: { $0.localURL != nil }), let url = port.localURL, let hostPort = port.publicPort {
                    PortLink(title: "localhost:\(hostPort)", url: url, showsArrow: true)
                } else {
                    Text("—").foregroundStyle(Palette.secondary)
                }
            }
            .font(.mono(12))
            .frame(width: columns.port, alignment: .leading)

            HStack(spacing: 2) {
                Button {
                    Clipboard.copy(command)
                    containers.showToast("Copied \(command)")
                } label: {
                    Label { Text("Copy exec command") } icon: { LineIcon(kind: .copy).icon(Palette.text, size: 14) }
                }
                .buttonStyle(ToolbarIconButtonStyle(width: 28))
                .help("Copy “\(command)”")

                Menu {
                    ContainerMenu(container: container)
                } label: {
                    Hoverable { hovered in
                        HStack(spacing: 2.5) {
                            ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.text).frame(width: 3.5, height: 3.5) }
                        }
                        .frame(width: 28, height: 28)
                        .background(hovered ? Palette.hover : .clear, in: .capsule)
                        .contentShape(.capsule)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
                .accessibilityLabel("More actions")
            }
            .frame(width: GroupColumns.actions, alignment: .trailing)
        }
        // The 28 pt star plus the gap fill the 44 pt gutter, so the dot keeps its column.
        .padding(.leading, GroupColumns.leading - 28 - GroupColumns.gap)
        .padding(.trailing, GroupColumns.trailing)
        .frame(height: 48)
        .background(favorites.contains(container) ? Palette.favoriteWash : .clear)
        .rowWash(isSelected: containers.selectedID == container.id)
        .overlay(alignment: .top) { Palette.rowDivider.frame(height: 1) }
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

/// Favorites.dc.html star: gold when on, a grey outline otherwise.
struct FavoriteStar: View {
    let isOn: Bool
    let size: CGFloat
    let label: String
    var disabledHelp: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: size * 0.8, weight: .medium))
                .foregroundStyle(isOn ? Palette.favorite : Palette.grayDot)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(disabledHelp ?? (isOn ? "Remove \(label) from favorites" : "Add \(label) to favorites"))
        .accessibilityLabel(isOn ? "Remove \(label) from favorites" : "Add \(label) to favorites")
    }
}

/// "Copied …" capsule shown at the bottom of the content.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            LineIcon(kind: .check).icon(Palette.greenDot, size: 14, svgStrokeWidth: 2.6)
            Text(message).font(.mono(12))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(white: 0.11, opacity: 0.86), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
