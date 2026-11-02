import AppKit
import ColiUICore
import SwiftUI
import UniformTypeIdentifiers

/// Detail.dc.html: header (60 pt), tabs capsule, then the logs panel beside the info cards.
struct ContainerDetailView: View {
    @Environment(AppModel.self) private var model
    let detail: ContainerDetailViewModel

    /// The live list entry (status changes arrive through Docker events).
    private var container: Container? {
        model.containers.containers.first { $0.id == detail.containerID }
    }

    var body: some View {
        @Bindable var detail = detail
        @Bindable var containers = model.containers
        let pendingRemoval = containers.pendingRemoval
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(detail: detail, container: container)
            CapsuleSegmented(
                options: DetailTab.allCases.map { SegmentOption(value: $0, title: $0.rawValue) },
                selection: $detail.tab
            )
            .padding(.horizontal, 16)

            HStack(alignment: .top, spacing: 16) {
                Group {
                    if detail.tab == .logs {
                        LogsSection(detail: detail, name: container?.name ?? detail.details?.name ?? "container")
                    } else {
                        Text("Designed, not built yet.")
                            .font(.ui(13))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(48)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                InfoCards(details: detail.details, container: container)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 320)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { containers.pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { container in
            Button("Remove", role: .destructive) {
                Task {
                    await containers.perform(.remove, on: container)
                    model.closeDetail()
                }
            }
        } message: { container in
            Text(container.isRunning ? "It's running and will be stopped first. This can't be undone." : "This can't be undone.")
        }
    }
}

private struct DetailHeader: View {
    @Environment(AppModel.self) private var model
    let detail: ContainerDetailViewModel
    let container: Container?

    var body: some View {
        let containers = model.containers
        let name = container?.name ?? detail.details?.name ?? ""
        let image = container?.image ?? detail.details?.image ?? ""
        HStack(spacing: 10) {
            GlassCapsule {
                Button { model.closeDetail() } label: {
                    Label { Text("Back") } icon: { LineIcon(kind: .chevronLeft).icon(Palette.text, size: 16, svgStrokeWidth: 2.2) }
                }
                .buttonStyle(ToolbarIconButtonStyle(width: 28))
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to containers (⌘[)")
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.ui(15, .semibold))
                Text("\(String(detail.containerID.prefix(12))) · \(image)")
                    .font(.mono(11))
                    .foregroundStyle(Palette.secondary)
            }

            if let container {
                StatusPill(container: container)
            }

            Spacer(minLength: 10)

            if let container {
                let isBusy = containers.busyIDs.contains(container.id)
                GlassCapsule {
                    if isBusy {
                        ProgressView().controlSize(.small).frame(width: 34, height: 28)
                    } else if container.isRunning {
                        Button { Task { await containers.perform(.stop, on: container) } } label: {
                            Label {
                                Text("Stop")
                            } icon: {
                                RoundedRectangle(cornerRadius: 13 / 12).fill(Palette.text).frame(width: 7.6, height: 7.6).frame(width: 13, height: 13)
                            }
                        }
                        .help("Stop \(container.name)")
                    } else {
                        Button { Task { await containers.perform(.start, on: container) } } label: {
                            Label { Text("Start") } icon: { PlayShape().fill(Palette.greenText).frame(width: 13, height: 13) }
                        }
                        .help("Start \(container.name)")
                    }
                    Button { Task { await containers.perform(.restart, on: container) } } label: {
                        Label { Text("Restart") } icon: { LineIcon(kind: .refresh).icon(Palette.text, size: 15, svgStrokeWidth: 2.2) }
                    }
                    .help("Restart \(container.name)")
                    Button { detail.tab = .terminal } label: {
                        Label { Text("Open shell") } icon: { LineIcon(kind: .terminal).icon(Palette.text, size: 16) }
                    }
                    .help("Open a shell in \(container.name)")
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .disabled(isBusy)

                GlassCapsule {
                    Button { containers.pendingRemoval = container } label: {
                        Label { Text("Remove") } icon: { LineIcon(kind: .trash).icon(Palette.danger, size: 15) }
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Remove \(container.name)…")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }
}

private struct StatusPill: View {
    let container: Container

    var body: some View {
        let failed = container.statusTextColor == Palette.orangeText
        HStack(spacing: 5) {
            Circle().fill(container.statusTint).frame(width: 7, height: 7)
            Text(container.status).lineLimit(1)
        }
        .font(.ui(12, .semibold))
        .foregroundStyle(container.statusTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(container.isRunning ? Palette.greenPill : failed ? Palette.orangePill : Palette.field, in: .capsule)
    }
}

private struct LogsSection: View {
    let detail: ContainerDetailViewModel
    let name: String

    var body: some View {
        @Bindable var detail = detail
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                HStack(spacing: 6) {
                    LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                    TextField("Filter logs", text: $detail.filterText)
                        .textFieldStyle(.plain)
                        .font(.ui(13))
                }
                .padding(.horizontal, 12)
                .frame(width: 220, height: 34)
                .background(Palette.field, in: .capsule)

                Button { detail.useRegex.toggle() } label: { Text(".*").font(.mono(12)) }
                    .buttonStyle(PillButtonStyle(isOn: detail.useRegex, foreground: detail.isRegexValid ? nil : Palette.danger))
                    .help(detail.isRegexValid ? "Use a regular expression" : "Invalid regular expression")

                Toggle(isOn: $detail.follow) { Text("Follow") }
                    .toggleStyle(.checkbox)
                    .pillSurface()
                    .help("Keep scrolling to the newest line")

                Toggle(isOn: $detail.showTimestamps) { Text("Timestamps") }
                    .toggleStyle(.checkbox)
                    .pillSurface()
                    .help("Show the time of each line")

                HStack(spacing: 4) {
                    Text("Since").fixedSize()
                    Menu(detail.range.rawValue) {
                        ForEach(LogRange.allCases) { range in
                            Button(range.rawValue) { detail.select(range: range) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .pillSurface()
                .help("How far back to load")

                Button(action: export) {
                    HStack(spacing: 6) {
                        LineIcon(kind: .download).icon(Palette.text, size: 13)
                        Text("Export")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .help("Save the visible lines as a .log file")

                Button("Clear") { detail.clear() }
                    .buttonStyle(PillButtonStyle())
                    .help("Clear the lines shown")
            }

            LogPanel(detail: detail)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).log"
        panel.allowedContentTypes = [.log]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? detail.exportText().write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct LogPanel: View {
    let detail: ContainerDetailViewModel

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        let lines = detail.visibleLines
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        LogRow(line: line, time: line.timestamp.map(Self.time.string(from:)), showTime: detail.showTimestamps)
                    }
                    if let error = detail.streamError {
                        Text(error).foregroundStyle(Palette.logError).padding(.top, 6)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .font(.mono(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .defaultScrollAnchor(.bottom)
            .background(Palette.logBackground, in: .rect(cornerRadius: 14))
            .overlay {
                if lines.isEmpty, detail.streamError == nil {
                    Text(detail.lines.isEmpty ? "No logs in this range. Try a longer “Since”." : "No lines match the filter.")
                        .font(.mono(12))
                        .foregroundStyle(Palette.logTime)
                }
            }
            .frame(minHeight: 470, maxHeight: .infinity)
            .onChange(of: detail.lines.last?.id) {
                if detail.follow { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

private struct LogRow: View {
    let line: LogLine
    let time: String?
    let showTime: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if showTime {
                Text(time ?? "        ").foregroundStyle(Palette.logTime)
            }
            Text(line.level.map { $0.rawValue.uppercased() } ?? "")
                .foregroundStyle(color)
                .frame(width: 44, alignment: .leading)
            Text(line.message)
                .foregroundStyle(Palette.logText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 20.4, alignment: .leading)
    }

    private var color: Color {
        switch line.level {
        case .info: Palette.logInfo
        case .warn: Palette.logWarn
        case .error: Palette.logError
        case .debug, nil: Palette.logTime
        }
    }
}

private struct InfoCards: View {
    let details: ContainerDetails?
    let container: Container?

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            card("OVERVIEW", spacing: 12) {
                row("Image", details?.image ?? container?.image ?? "—")
                row("Created", details?.created.map { Self.relative.localizedString(for: $0, relativeTo: Date()) } ?? "—")
                row("Restart policy", details?.restartPolicy ?? "—")
                row("Network", details?.network ?? "—")
                row("IP", details?.ipAddress ?? "—")
            }
            card("PORTS", spacing: 10) {
                let published = (container?.ports ?? []).filter { $0.localURL != nil }
                if published.isEmpty {
                    Text("—").font(.mono(12)).foregroundStyle(Palette.secondary)
                }
                ForEach(published, id: \.self) { port in
                    if let url = port.localURL, let hostPort = port.publicPort {
                        // `verbatim`: a localized string key would format 8002 as "8.002".
                        HStack(spacing: 6) {
                            PortLink(title: "localhost:\(hostPort)", url: url)
                            Text(verbatim: "→ \(port.privatePort)/\(port.proto)")
                                .foregroundStyle(Palette.secondary)
                        }
                        .font(.mono(12))
                    }
                }
            }
            card("MOUNTS", spacing: 10) {
                let mounts = details?.mounts ?? []
                if mounts.isEmpty {
                    Text("—").font(.mono(12)).foregroundStyle(Palette.secondary)
                }
                ForEach(mounts, id: \.self) { mount in
                    Text("\(Self.abbreviated(mount.source)) → \(mount.destination)")
                        .font(.mono(12))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.ui(11, .semibold))
                .tracking(0.44)
                .foregroundStyle(Palette.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            Text(value).font(.mono(12)).multilineTextAlignment(.trailing).lineLimit(2).textSelection(.enabled)
        }
        .font(.ui(12))
    }

    private static func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
