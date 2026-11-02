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
        .background(Palette.card, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
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
                Text(group.name).font(.ui(14, .semibold))
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

            if running > 0 {
                Button("Stop all") { Task { await containers.perform(.stopAll, on: group) } }
                    .buttonStyle(PillButtonStyle())
                    .help("Stop the running containers of \(group.name)")
            } else {
                Button { Task { await containers.perform(.startAll, on: group) } } label: {
                    Text("Start all").fontWeight(.semibold)
                }
                .buttonStyle(PillButtonStyle(foreground: Palette.greenText))
                .help("Start every container of \(group.name)")
            }
            Button("Restart") { Task { await containers.perform(.restart, on: group) } }
                .buttonStyle(PillButtonStyle())
                .help("Restart every container of \(group.name)")
            if let file = group.configFile {
                Button("Edit compose file") { NSWorkspace.shared.open(URL(fileURLWithPath: file)) }
                    .buttonStyle(PillButtonStyle())
                    .help("Open \(abbreviate(file)) in your editor")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
        HStack(spacing: GroupColumns.gap) {
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
        .padding(.leading, GroupColumns.leading)
        .padding(.trailing, GroupColumns.trailing)
        .frame(height: 48)
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
