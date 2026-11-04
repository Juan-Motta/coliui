import AppKit
import ColiUICore
import SwiftUI

/// MenuBar.dc.html: header with Quit, VM controls and status, CPU / RAM charts, disk bar, containers,
/// Open ColiUI and Settings. Restart, Stop and Quit ask first, in the panel.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let colima = model.colima
        let containers = model.containers
        VStack(alignment: .leading, spacing: 12) {
            header

            if let offer = model.updates.offer {
                UpdateBanner(version: offer.version) {
                    openMainWindow()
                    model.viewUpdate()
                }
            }

            if model.usesColima {
                colimaControls
                if colima.isRunning, let instance = colima.instance {
                    usage(instance: instance, sample: colima.resourceUsage)
                }
            } else {
                otherEngine
            }

            if model.isEngineRunning {
                let list = model.menuBarList
                HStack {
                    HStack(spacing: 5) {
                        if list.kind == .favorites {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Palette.favorite)
                        }
                        caption(list.kind == .favorites ? "FAVORITES" : "CONTAINERS")
                    }
                    Spacer()
                    Text(list.kind == .favorites
                         ? "\(list.shownCount) running"
                         : "\(containers.runningCount) of \(containers.containers.count) running")
                        .font(.ui(11))
                        .foregroundStyle(Palette.sidebarSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
                // On a card like CPU, RAM and DISK so the list reads well over whatever is behind the glass.
                VStack(spacing: 4) {
                    ForEach(list.groups) { group in
                        MenuBarGroup(group: group)
                    }
                    if containers.containers.isEmpty {
                        Text("No containers").font(.ui(13)).foregroundStyle(Palette.sidebarSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
                .padding(4)
                .background(Palette.menuCard, in: .rect(cornerRadius: 14))
            }

            HStack(spacing: 8) {
                Button(action: openMainWindow) {
                    Text("Open ColiUI").font(.ui(13, .medium)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuPillStyle())
                Button {
                    openMainWindow()
                    model.isSettingsPresented = true
                } label: {
                    LineIcon(kind: .settings).icon(Palette.text, size: 16)
                }
                .buttonStyle(MenuRoundStyle(side: 32, filled: true))
                .help("Settings")
            }
        }
        .padding(12)
        .frame(width: 336)
        .overlay {
            if let question = model.menuConfirmation {
                ConfirmationOverlay(question: question) { confirm(question) }
            }
        }
        .task {
            model.startPolling()
            // Samples only while the popover is open, and only Colima's VM (`colima ssh` each time).
            while !Task.isCancelled {
                if model.usesColima { await colima.refreshResourceUsage() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: Glyph.menuBarImage(dimmed: false, side: 24))
            VStack(alignment: .leading, spacing: 0) {
                Text("ColiUI").font(.ui(14, .semibold))
                Text(verbatim: model.usesColima ? "Profile: \(model.colima.profile)" : model.engineKind.displayName)
                    .font(.ui(11))
                    .foregroundStyle(Palette.sidebarSecondary)
            }
            Spacer()
            Button { model.menuConfirmation = .quit } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(MenuRoundStyle(side: 28, filled: true))
            .keyboardShortcut("q")
            .help("Quit ColiUI (⌘Q)")
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var colimaControls: some View {
        let colima = model.colima
        return HStack(spacing: 4) {
            if colima.isRunning {
                Button { model.menuConfirmation = .restart } label: {
                    LineIcon(kind: .refresh).icon(Palette.text, size: 15, svgStrokeWidth: 2.2)
                }
                .help("Restart Colima")
                Button { model.menuConfirmation = .stop } label: {
                    RoundedRectangle(cornerRadius: 1.5).fill(Palette.text).frame(width: 10, height: 10)
                }
                .help("Stop Colima")
            } else {
                Button { Task { await model.performColima(.start) } } label: {
                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(Palette.greenText)
                }
                .help("Start Colima")
            }
            Spacer()
            StatePill(title: colima.statusTitle, isOn: colima.isRunning, isBusy: colima.isBusy)
        }
        .buttonStyle(MenuRoundStyle(side: 30, filled: false))
        .disabled(colima.isBusy)
        .padding(.horizontal, 2)
    }

    private func usage(instance: ColimaInstance, sample: ColimaResourceUsage?) -> some View {
        let colima = model.colima
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ResourceCard(title: "CPU", size: "\(instance.cpus) cores", value: sample?.cpuDisplay ?? "—",
                             level: (sample?.cpuPercent ?? 0) / 100, history: colima.cpuHistory)
                ResourceCard(title: "RAM", size: instance.memoryDisplay,
                             value: sample.map { ByteFormat.binary($0.memoryUsedBytes) } ?? "—",
                             level: sample?.memoryLevel ?? 0, history: colima.memoryHistory)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    caption("DISK")
                    Spacer()
                    Text(sample.map { "\(ByteFormat.binary($0.diskUsedBytes)) / \(ByteFormat.binary($0.diskTotalBytes))" } ?? "—")
                        .font(.ui(11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.sidebarSecondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(Palette.progressTrack)
                        .overlay(alignment: .leading) {
                            Capsule().fill(UsageTint.color(for: sample?.diskLevel ?? 0))
                                .frame(width: geometry.size.width * (sample?.diskLevel ?? 0))
                        }
                }
                .frame(height: 6)
            }
            .padding(10)
            .background(Palette.menuCard, in: .rect(cornerRadius: 14))
        }
    }

    /// Engines.dc.html › Menu bar popover for Docker Desktop, OrbStack and the rest.
    @ViewBuilder private var otherEngine: some View {
        HStack {
            Spacer()
            StatePill(title: model.isEngineRunning ? "Running" : "Not running", isOn: model.isEngineRunning, isBusy: false)
        }
        if let info = model.engineInfo {
            HStack(spacing: 8) {
                MetricTile(title: "CPU", value: "\(info.cpus) cores")
                MetricTile(title: "Memory", value: info.memoryText)
                MetricTile(title: "Disk", value: model.cleanup.usage.map { "\(ByteFormat.binary($0.totalBytes)) used" } ?? "—")
            }
        }
        if model.engineApp != nil {
            Button { model.openEngineApp() } label: {
                Text(verbatim: "Open \(model.engineKind.displayName)").font(.ui(13)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MenuPillStyle())
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.ui(11, .semibold)).tracking(0.44).foregroundStyle(Palette.sidebarSecondary)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func confirm(_ question: MenuConfirmation) {
        model.menuConfirmation = nil
        switch question {
        case .restart: Task { await model.performColima(.restart) }
        case .stop: Task { await model.performColima(.stop) }
        case .quit: NSApp.terminate(nil)
        }
    }
}

/// The in-panel question before restarting or stopping the VM, or quitting (AppModel keeps it, not `@State`).
enum MenuConfirmation {
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

    var confirmTitle: String {
        switch self {
        case .restart: "Restart"
        case .stop: "Stop"
        case .quit: "Quit"
        }
    }

    var confirmColor: Color { self == .stop ? Palette.destructive : Palette.tint }
}

/// MenuBar.dc.html confirmation: dimmed panel, a small glass card, Cancel and the action.
private struct ConfirmationOverlay: View {
    @Environment(AppModel.self) private var model
    let question: MenuConfirmation
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Palette.modalBackdrop
                .contentShape(.rect)
                .onTapGesture { model.menuConfirmation = nil }
            VStack(spacing: 8) {
                Text(question.title).font(.ui(14, .semibold))
                Text(question.message)
                    .font(.ui(12))
                    .foregroundStyle(Palette.sidebarSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { model.menuConfirmation = nil } label: {
                        Text("Cancel").font(.ui(13)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MenuPillStyle())
                    .keyboardShortcut(.cancelAction)
                    Button(action: onConfirm) {
                        Text(question.confirmTitle).font(.ui(13, .semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MenuPillStyle(fill: question.confirmColor, foreground: .white))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
            .padding(16)
            .frame(maxWidth: 260)
            .background(Palette.modalSurface, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.glassBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 20, y: 9)
            .padding(20)
        }
    }
}

/// `.pill`: 32 pt capsule on a 6 % fill, or a solid colour for the confirm action.
private struct MenuPillStyle: ButtonStyle {
    var fill: Color? = nil
    var foreground: Color = Palette.text

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .foregroundStyle(foreground)
                .frame(height: 32)
                .background(fill ?? (hovered ? Palette.fieldHover : Palette.chip), in: .capsule)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(.capsule)
        }
    }
}

/// `.ib`: a round icon button; `filled` adds the 6 % disc (Quit, Settings).
private struct MenuRoundStyle: ButtonStyle {
    let side: CGFloat
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .foregroundStyle(Palette.text)
                .frame(width: side, height: side)
                .background(filled || hovered ? (hovered ? Palette.hover : Palette.chip) : .clear, in: .circle)
                .contentShape(.circle)
        }
    }
}

/// The status pill: green dot and text on a pale green capsule when running, grey otherwise.
private struct StatePill: View {
    let title: String
    let isOn: Bool
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(isOn ? Palette.greenDot : Palette.grayDot).frame(width: 7, height: 7)
            }
            Text(title)
        }
        .font(.ui(12, .semibold))
        .foregroundStyle(isOn && !isBusy ? Palette.greenText : Palette.sidebarSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isOn && !isBusy ? Palette.greenPill : Palette.chip, in: .capsule)
    }
}

/// `.card`: CPU or RAM with its size, the current value and the last samples as a tinted area.
private struct ResourceCard: View {
    let title: String
    let size: String
    let value: String
    let level: Double
    let history: [Double]

    var body: some View {
        let tint = UsageTint.color(for: level)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.ui(11, .semibold)).tracking(0.44).foregroundStyle(Palette.sidebarSecondary)
                Spacer()
                Text(size).font(.ui(11)).monospacedDigit().foregroundStyle(Palette.sidebarSecondary)
            }
            Text(value).font(.ui(15, .semibold)).monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(alignment: .bottom) {
            if history.count > 1 {
                ZStack {
                    UsageArea(values: history).fill(tint.opacity(0.18))
                    UsageLine(values: history).stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 36)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
        }
        .background(Palette.menuCard, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
    }
}

/// Green under 60 %, orange under 85 %, then red — the Cleanup and Live stats colours.
enum UsageTint {
    static func color(for level: Double) -> Color {
        switch level {
        case ..<0.6: Palette.switchOn
        case ..<0.85: Palette.orangeDot
        default: Palette.destructive
        }
    }
}

private struct UsageLine: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat(min(max(value, 0), 1)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

private struct UsageArea: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        var area = UsageLine(values: values).path(in: rect)
        area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        area.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        area.closeSubpath()
        return area
    }
}

/// Engines.dc.html tiles for engines ColiUI can't sample (CPU cores, memory, disk used).
private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(11)).foregroundStyle(Palette.sidebarSecondary)
            Text(value).font(.ui(15, .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.menuCard, in: .rect(cornerRadius: 14))
    }
}

/// One Compose project (or Standalone) in the popover: fold arrow, icon, name, running / total, and the
/// project's Restart all / Stop all (Start all when nothing runs); its containers below, indented.
private struct MenuBarGroup: View {
    @Environment(AppModel.self) private var model
    let group: ComposeGroup

    var body: some View {
        let containers = model.containers
        let isOpen = !model.menuCollapsedGroups.contains(group.id)
        let running = group.runningCount
        let total = group.containers.count
        VStack(spacing: 2) {
            Hoverable { hovered in
                HStack(spacing: 8) {
                    Button { model.toggleMenuGroup(group.id) } label: {
                        LineIcon(kind: .chevronRight).icon(Palette.sidebarSecondary, size: 11, svgStrokeWidth: 2.6)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .buttonStyle(MenuRoundStyle(side: 20, filled: false))
                    .help(isOpen ? "Collapse \(group.name)" : "Expand \(group.name)")
                    if group.isStandalone {
                        LineIcon(kind: .containers).icon(Palette.sidebarSecondary, size: 15)
                    } else {
                        LineIcon(kind: .folder).icon(Palette.accent, size: 15)
                    }
                    Text(group.name).font(.ui(13, .semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(running) / \(total)")
                        .font(.ui(11, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(running == 0 ? Palette.secondary : running < total ? Palette.orangeText : Palette.greenText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(running == 0 ? Palette.field : running < total ? Palette.orangePill : Palette.greenPill, in: .capsule)
                    if !group.isStandalone {
                        if running > 0 {
                            Button { Task { await containers.perform(.restart, on: group) } } label: {
                                LineIcon(kind: .refresh).icon(Palette.text, size: 13, svgStrokeWidth: 2.2)
                            }
                            .help("Restart all in \(group.name)")
                            Button { Task { await containers.perform(.stopAll, on: group) } } label: {
                                RoundedRectangle(cornerRadius: 1.5).fill(Palette.text).frame(width: 9, height: 9)
                            }
                            .help("Stop all in \(group.name)")
                        } else {
                            Button { Task { await containers.perform(.startAll, on: group) } } label: {
                                Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(Palette.greenText)
                            }
                            .help("Start all in \(group.name)")
                        }
                    }
                }
                .buttonStyle(MenuRoundStyle(side: 28, filled: false))
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .frame(height: 32)
                .background(hovered ? Palette.hoverSubtle : .clear, in: .rect(cornerRadius: 10))
            }
            if isOpen {
                ForEach(group.containers) { container in
                    MenuBarContainerRow(container: container)
                }
            }
        }
    }
}

/// `.mi`: 36 pt row with the state dot, name and status, and Restart + Stop (or Start).
private struct MenuBarContainerRow: View {
    @Environment(AppModel.self) private var model
    let container: Container

    var body: some View {
        let containers = model.containers
        Hoverable { hovered in
            HStack(spacing: 10) {
                Circle().fill(container.statusTint).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(container.composeService ?? container.name).font(.ui(13, .medium)).lineLimit(1)
                    Text(container.status).font(.ui(11)).foregroundStyle(Palette.sidebarSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if containers.busyIDs.contains(container.id) {
                    ProgressView().controlSize(.small).frame(width: 30, height: 30)
                } else if container.isRunning {
                    Button { Task { await containers.perform(.restart, on: container) } } label: {
                        LineIcon(kind: .refresh).icon(Palette.text, size: 13, svgStrokeWidth: 2.2)
                    }
                    .buttonStyle(MenuRoundStyle(side: 30, filled: false))
                    .help("Restart \(container.name)")
                    Button { Task { await containers.perform(.stop, on: container) } } label: {
                        RoundedRectangle(cornerRadius: 1.5).fill(Palette.text).frame(width: 9, height: 9)
                    }
                    .buttonStyle(MenuRoundStyle(side: 30, filled: false))
                    .help("Stop \(container.name)")
                } else {
                    Button { Task { await containers.perform(.start, on: container) } } label: {
                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(Palette.greenText)
                    }
                    .buttonStyle(MenuRoundStyle(side: 30, filled: false))
                    .help("Start \(container.name)")
                }
            }
            .padding(.leading, 34)
            .padding(.trailing, 4)
            .frame(height: 36)
            .background(hovered ? Palette.hoverSubtle : .clear, in: .rect(cornerRadius: 10))
        }
    }
}
