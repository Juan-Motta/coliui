import ColiUICore
import SwiftUI

/// Cleanup.dc.html: disk card, reclaimable options, glass footer.
struct CleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var cleanup = model.cleanup
        VStack(alignment: .leading, spacing: 0) {
            CleanupHeader()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    DiskCard()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reclaimable").font(.ui(15, .semibold))
                        ForEach(PruneTarget.allCases, id: \.self) { target in
                            OptionCard(target: target)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            CleanupFooter()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .confirmationDialog(
            "Free \(ByteFormat.short(cleanup.selectedBytes))?",
            isPresented: $cleanup.confirmingCleanup
        ) {
            Button("Clean up", role: .destructive) { Task { await cleanup.cleanUp() } }
        } message: {
            Text(cleanup.selected.contains(.volumes)
                 ? "Unused volumes and their data will be deleted permanently. This can't be undone."
                 : "This can't be undone.")
        }
    }
}

private struct CleanupHeader: View {
    @Environment(AppModel.self) private var model

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        let cleanup = model.cleanup
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cleanup").font(.ui(15, .semibold))
                // Re-rendered every 30 s so "Last scanned 2 min ago" doesn't go stale.
                TimelineView(.periodic(from: .now, by: 30)) { _ in Text(subtitle(cleanup)) }
                    .font(.ui(11))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            GlassCapsule {
                Button { Task { await cleanup.scan() } } label: {
                    HStack(spacing: 6) {
                        LineIcon(kind: .refresh).icon(Palette.text, size: 14)
                        Text("Rescan").font(.ui(12))
                    }
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(cleanup.isScanning || cleanup.isCleaning)
                .help("Measure disk usage again")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }

    private func subtitle(_ cleanup: CleanupViewModel) -> String {
        if cleanup.isCleaning { return "Cleaning up…" }
        if cleanup.isScanning { return "Scanning…" }
        guard let scanned = cleanup.lastScan else { return "Not scanned yet" }
        return "Last scanned \(Self.relative.localizedString(for: scanned, relativeTo: Date()))"
    }
}

private struct DiskCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let usage = model.cleanup.usage
        let capacity = max(model.colima.instance?.diskBytes ?? 0, usage?.totalBytes ?? 0)
        let segments: [(String, Color, Int64)] = [
            ("Images", Palette.diskImages, usage?.images.totalBytes ?? 0),
            ("Build cache", Palette.diskCache, usage?.buildCache.totalBytes ?? 0),
            ("Volumes", Palette.diskVolumes, usage?.volumes.totalBytes ?? 0),
            ("Containers", Palette.diskContainers, usage?.containers.totalBytes ?? 0),
        ]
        let used = usage?.totalBytes ?? 0
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Colima VM disk · \(model.colima.profile)").font(.ui(15, .semibold))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: ByteFormat.binary(used)).font(.ui(20, .semibold))
                    Text(verbatim: capacity > 0 ? "of \(ByteFormat.binary(capacity)) used by Docker" : "used by Docker")
                        .font(.ui(13))
                        .foregroundStyle(Palette.tertiary)
                }
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments, id: \.0) { _, color, bytes in
                        if bytes > 0, capacity > 0 {
                            color.frame(width: max(geometry.size.width * CGFloat(bytes) / CGFloat(capacity), 2))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            .background(Palette.field)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityElement()
            .accessibilityLabel(segments.map { "\($0.0) \(ByteFormat.binary($0.2))" }.joined(separator: ", "))

            FlowLayout(spacing: 20, lineSpacing: 8) {
                ForEach(segments, id: \.0) { name, color, bytes in
                    legend(color: color, text: "\(name) \(ByteFormat.binary(bytes))")
                }
                if capacity > 0 {
                    legend(color: Palette.field, text: "Free \(ByteFormat.binary(max(capacity - used, 0)))")
                }
            }

            Text("Colima disks can only grow — freeing space inside the VM is the only way to reclaim it.")
                .font(.ui(12))
                .foregroundStyle(Palette.secondary)
        }
        .padding(20)
        .cardSurface()
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 10, height: 10)
            Text(verbatim: text)
        }
        .font(.ui(12))
        .foregroundStyle(Palette.tertiary)
    }
}

private struct OptionCard: View {
    @Environment(AppModel.self) private var model
    let target: PruneTarget

    var body: some View {
        let cleanup = model.cleanup
        let category = cleanup.usage?.category(target)
        let isOn = cleanup.selected.contains(target)
        let items = category?.reclaimableItems ?? []
        HStack(alignment: .center, spacing: 14) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in cleanup.toggle(target) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(14, .medium))
                Text(description(items)).font(.ui(12)).foregroundStyle(Palette.secondary).lineLimit(1)
                if target == .volumes {
                    HStack(spacing: 4) {
                        LineIcon(kind: .warning).icon(Palette.orangeText, size: 12, svgStrokeWidth: 2.4)
                        Text("Deletes data permanently")
                    }
                    .font(.ui(12))
                    .foregroundStyle(Palette.orangeText)
                }
                if cleanup.showItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(items.prefix(8), id: \.self) { Text(verbatim: $0) }
                        if items.count > 8 { Text(verbatim: "and \(items.count - 8) more") }
                    }
                    .font(.mono(11))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 4)
                    .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: count(items.count)).font(.ui(12)).foregroundStyle(Palette.secondary)
            Text(verbatim: ByteFormat.short(category?.reclaimableBytes ?? 0))
                .font(.ui(15, .semibold))
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isOn ? Palette.optionSelected : Palette.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOn ? Palette.optionSelectedBorder : Palette.cardBorder, lineWidth: 1))
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { cleanup.toggle(target) }
    }

    private var title: String {
        switch target {
        case .images: "Dangling & unused images"
        case .containers: "Stopped containers"
        case .volumes: "Unused volumes"
        case .buildCache: "Build cache"
        }
    }

    private func description(_ items: [String]) -> String {
        switch target {
        case .images: "Untagged layers and images no container uses"
        case .containers: items.isEmpty ? "No stopped containers" : items.joined(separator: ", ")
        case .volumes: "Not mounted by any container"
        case .buildCache: "BuildKit cache no build is using"
        }
    }

    private func count(_ n: Int) -> String {
        switch target {
        case .images: "\(n) image\(n == 1 ? "" : "s")"
        case .containers: "\(n) container\(n == 1 ? "" : "s")"
        case .volumes: "\(n) volume\(n == 1 ? "" : "s")"
        case .buildCache: "\(n) entr\(n == 1 ? "y" : "ies")"
        }
    }
}

private struct CleanupFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleanup = model.cleanup
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let freed = cleanup.lastFreedBytes {
                    Text(verbatim: "Freed \(ByteFormat.short(freed)) ·").foregroundStyle(Palette.greenText)
                }
                Text("Selected:").foregroundStyle(Palette.tertiary)
                Text(verbatim: ByteFormat.short(cleanup.selectedBytes)).font(.ui(17, .semibold))
                Text("to free").foregroundStyle(Palette.tertiary)
            }
            .font(.ui(13))
            if let error = cleanup.errorMessage {
                Text(error).font(.ui(12)).foregroundStyle(Palette.danger).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(cleanup.showItems ? "Hide items" : "Review items…") { cleanup.showItems.toggle() }
                .buttonStyle(PillButtonStyle())
                .help("List what each option would remove")
            Button {
                cleanup.confirmingCleanup = true
            } label: {
                HStack(spacing: 6) {
                    if cleanup.isCleaning { ProgressView().controlSize(.mini).tint(.white) }
                    Text("Clean up selected")
                }
            }
            .buttonStyle(DestructiveButtonStyle())
            .disabled(cleanup.selectedBytes == 0 || cleanup.isCleaning || cleanup.isScanning)
            .help("Remove the selected items")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassSurface(RoundedRectangle(cornerRadius: 24))
    }
}

/// `.danger`: red capsule for destructive actions.
private struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.ui(13, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Palette.destructive.opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : hovered ? 0.9 : 1), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: Palette.destructive.opacity(isEnabled ? 0.3 : 0), radius: 7, y: 4)
                .contentShape(.capsule)
        }
    }
}
