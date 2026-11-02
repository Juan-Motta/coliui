import AppKit
import ColiUICore
import SwiftUI

/// Volumes.dc.html: header (60 pt), optional create bar, filter row with the data warning, then the volumes card.
struct VolumesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var volumes = model.volumes
        let pendingRemoval = volumes.pendingRemoval
        VStack(alignment: .leading, spacing: 0) {
            VolumesHeader()
            VStack(alignment: .leading, spacing: 14) {
                if volumes.isCreateBarOpen {
                    CreateVolumeBar()
                }
                HStack {
                    CapsuleSegmented(
                        options: VolumeFilter.allCases.map {
                            SegmentOption(value: $0, title: "\($0.rawValue) (\(volumes.count(for: $0)))")
                        },
                        selection: $volumes.filter
                    )
                    Spacer()
                    HStack(spacing: 4) {
                        LineIcon(kind: .warning).icon(Palette.orangeText, size: 12, svgStrokeWidth: 2.4)
                        Text("Removing a volume deletes its data permanently")
                    }
                    .font(.ui(12))
                    .foregroundStyle(Palette.orangeText)
                }
                if volumes.volumes.isEmpty {
                    ContentUnavailableView(
                        volumes.isLoading ? "Loading volumes…" : "No volumes",
                        systemImage: "externaldrive",
                        description: Text(volumes.errorMessage ?? "Containers create volumes to keep data between runs.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VolumesCard()
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .animation(.easeOut(duration: 0.2), value: volumes.isCreateBarOpen)
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { volumes.pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { volume in
            Button("Remove", role: .destructive) { Task { await volumes.remove(volume) } }
        } message: { volume in
            Text("Everything stored in it\(volume.size.map { " (\(ByteFormat.short($0)))" } ?? "") is deleted. This can't be undone.")
        }
        .overlay(alignment: .bottom) {
            if let error = volumes.errorMessage, !volumes.volumes.isEmpty {
                ErrorBanner(message: error) { volumes.errorMessage = nil }
                    .padding(.bottom, 16)
            } else if let toast = volumes.toast {
                ToastView(message: toast).padding(.bottom, 20)
            }
        }
        .animation(.easeOut(duration: 0.2), value: volumes.toast)
    }
}

/// Title + subtitle, spacer, refresh/sort capsule, search capsule, New volume.
private struct VolumesHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var volumes = model.volumes
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Volumes").font(.ui(15, .semibold))
                Text(verbatim: volumes.summary)
                    .font(.ui(11))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.trailing, 6)

            Spacer(minLength: 10)

            GlassCapsule {
                Button { Task { await volumes.refresh() } } label: {
                    Label { Text("Refresh") } icon: { LineIcon(kind: .refresh).icon(Palette.text, size: 16) }
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")

                Menu {
                    Picker("Sort by", selection: $volumes.sort) {
                        ForEach(VolumeSort.allCases) { Text($0.rawValue).tag($0) }
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
                .help("Sort by name, creation date or size")
                .accessibilityLabel("Sort")
            }

            HStack(spacing: 6) {
                LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                TextField("Search", text: $volumes.searchText)
                    .textFieldStyle(.plain)
                    .font(.ui(13))
            }
            .padding(.horizontal, 12)
            .frame(width: 200, height: 34)
            .glassSurface(Capsule())
            .help("Search by name or Compose project")

            Button { volumes.openCreateBar() } label: {
                HStack(spacing: 6) {
                    LineIcon(kind: .plus).icon(.white, size: 14, svgStrokeWidth: 2.4)
                    Text("New volume")
                }
            }
            .buttonStyle(TintButtonStyle())
            .keyboardShortcut("n")
            .help("Create a named volume (⌘N)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }
}

/// Glass bar: "Name" field, "Driver: local", Cancel, Create.
private struct CreateVolumeBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var volumes = model.volumes
        let showNameError = !volumes.newName.isEmpty && volumes.nameError != nil
        HStack(spacing: 10) {
            Text("Name").font(.ui(13, .medium))
            TextField("minio-data", text: $volumes.newName)
                .textFieldStyle(.plain)
                .font(.mono(12))
                .padding(.horizontal, 10)
                .frame(minWidth: 220, maxWidth: .infinity)
                .frame(height: 30)
                .background(Palette.field, in: .rect(cornerRadius: 10))
                .focused($focused)
                .disabled(volumes.isCreating)
                .onSubmit { Task { await volumes.create() } }

            if let error = volumes.createError ?? (showNameError ? volumes.nameError : nil) {
                Text(error)
                    .font(.ui(12))
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .leading)
            } else if volumes.isCreating {
                ProgressView().controlSize(.small)
            } else {
                Text("Driver: local").font(.ui(12)).foregroundStyle(Palette.secondary)
            }

            Button("Cancel") { volumes.closeCreateBar() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close")
            Button("Create") { Task { await volumes.create() } }
                .buttonStyle(TintButtonStyle())
                .disabled(volumes.isCreating || volumes.nameError != nil)
        }
        .padding(.leading, 16)
        .padding([.trailing, .vertical], 8)
        .glassSurface(RoundedRectangle(cornerRadius: 22))
        .onAppear { focused = true }
    }
}

/// `grid-template-columns: 2.6fr 0.8fr 1fr 0.9fr 2.2fr 84px; gap: 12px; padding: 0 16px`.
private struct VolumeColumns {
    static let actions: CGFloat = 84
    static let gap: CGFloat = 12
    static let padding: CGFloat = 16

    let name, driver, created, size, usedBy: CGFloat

    init(width: CGFloat) {
        let fractions = max(width - 2 * Self.padding - Self.actions - 5 * Self.gap, 0)
        let fr = fractions / 7.5
        name = 2.6 * fr
        driver = 0.8 * fr
        created = 1 * fr
        size = 0.9 * fr
        usedBy = 2.2 * fr
    }
}

private struct VolumesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let volumes = model.volumes
        GeometryReader { geometry in
            let columns = VolumeColumns(width: geometry.size.width)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    VolumesHeaderRow(columns: columns)
                    ForEach(volumes.visibleVolumes) { volume in
                        VolumeListRow(volume: volume, columns: columns)
                    }
                }
                .frame(width: geometry.size.width)
                .background(Palette.card)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .defaultScrollAnchor(.top)
        }
    }
}

private struct VolumesHeaderRow: View {
    let columns: VolumeColumns

    var body: some View {
        HStack(spacing: VolumeColumns.gap) {
            Text("NAME").frame(width: columns.name, alignment: .leading)
            Text("DRIVER").frame(width: columns.driver, alignment: .leading)
            Text("CREATED").frame(width: columns.created, alignment: .leading)
            Text("SIZE").frame(width: columns.size, alignment: .trailing)
            Text("USED BY").frame(width: columns.usedBy, alignment: .leading)
            Text("ACTIONS").frame(width: VolumeColumns.actions, alignment: .center)
        }
        .font(.ui(11, .semibold))
        .tracking(0.33)
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, VolumeColumns.padding)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }
    }
}

private struct VolumeListRow: View {
    @Environment(AppModel.self) private var model
    let volume: DockerVolume
    let columns: VolumeColumns

    var body: some View {
        let volumes = model.volumes
        let usedBy = volumes.usedBy(volume)
        Hoverable { hovered in
            HStack(spacing: VolumeColumns.gap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(volume.isAnonymous ? .mono(12, .medium) : .ui(13, .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(volume.name)
                    if let project = volume.composeProject {
                        Text(project)
                            .font(.ui(11))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Palette.chip, in: .capsule)
                            .help("Compose project “\(project)”")
                    }
                }
                .frame(width: columns.name, alignment: .leading)

                Text(volume.driver)
                    .font(.ui(12))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: columns.driver, alignment: .leading)

                Text(volume.created.map { ImageAge.text(for: $0) } ?? "—")
                    .font(.ui(12))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .frame(width: columns.created, alignment: .leading)
                    .help(volume.created?.formatted(date: .abbreviated, time: .shortened) ?? "")

                Text(volume.size.map(ByteFormat.short) ?? "—")
                    .font(.ui(12))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: columns.size, alignment: .trailing)

                HStack(spacing: 6) {
                    Circle().fill(usedBy.isEmpty ? Palette.grayDot : Palette.greenDot).frame(width: 8, height: 8)
                    Text(usedBy.isEmpty ? "Unused" : usedBy.joined(separator: ", ")).lineLimit(1)
                }
                .font(.ui(12))
                .foregroundStyle(usedBy.isEmpty ? Palette.secondary : Palette.greenText)
                .frame(width: columns.usedBy, alignment: .leading)
                .help(usedBy.isEmpty ? "No container mounts this volume" : "Mounted by \(usedBy.joined(separator: ", "))")

                VolumeActions(volume: volume, canRemove: usedBy.isEmpty)
                    .frame(width: VolumeColumns.actions, alignment: .center)
            }
            .padding(.horizontal, VolumeColumns.padding)
            .frame(height: 52)
            .background(hovered ? Palette.rowHover : .clear)
            .overlay(alignment: .bottom) { Palette.rowDivider.frame(height: 1) }
            .contentShape(.rect)
        }
        .contextMenu {
            Button("Copy Name") { VolumeActions.copy(volume.name) }
            Divider()
            Button("Remove…", role: .destructive) { volumes.pendingRemoval = volume }
                .disabled(!usedBy.isEmpty)
        }
    }
}

private struct VolumeActions: View {
    @Environment(AppModel.self) private var model
    let volume: DockerVolume
    let canRemove: Bool

    static func copy(_ text: String) {
        Clipboard.copy(text)
    }

    var body: some View {
        let volumes = model.volumes
        HStack(spacing: 2) {
            if volumes.removingNames.contains(volume.name) {
                ProgressView().controlSize(.small).frame(width: 58, height: 28)
            } else {
                Button {
                    Self.copy(volume.name)
                    volumes.showToast("Copied \(volume.name)")
                } label: {
                    Label { Text("Copy name") } icon: { LineIcon(kind: .copy).icon(Palette.text, size: 14) }
                }
                .help("Copy “\(volume.name)”")

                Button { volumes.pendingRemoval = volume } label: {
                    Label { Text("Remove") } icon: { LineIcon(kind: .trash).icon(Palette.danger, size: 14) }
                }
                .disabled(!canRemove)
                .opacity(canRemove ? 1 : 0.35)
                .help(canRemove ? "Remove \(volume.name)…" : "In use — remove its containers first")
            }
        }
        .buttonStyle(ToolbarIconButtonStyle(width: 28))
    }
}
