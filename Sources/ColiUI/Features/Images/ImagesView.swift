import ColiUICore
import SwiftUI

/// Images.dc.html: header (60 pt), optional pull bar, filter row, then the images card.
struct ImagesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var images = model.images
        let pendingRemoval = images.pendingRemoval
        VStack(alignment: .leading, spacing: 0) {
            ImagesHeader()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CapsuleSegmented(
                        options: ImageFilter.allCases.map {
                            SegmentOption(value: $0, title: "\($0.rawValue) (\(images.count(for: $0)))")
                        },
                        selection: $images.filter
                    )
                    Spacer()
                    Text("Images in use can't be removed while a container uses them")
                        .font(.ui(12))
                        .foregroundStyle(Palette.secondary)
                }
                if images.images.isEmpty {
                    ContentUnavailableView(
                        images.isLoading ? "Loading images…" : "No images",
                        systemImage: "square.stack.3d.up",
                        description: Text(images.errorMessage ?? "Pull an image to get started.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ImagesCard()
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval.map(Self.title) ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { images.pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { image in
            Button("Remove", role: .destructive) { Task { await images.remove(image) } }
        } message: { image in
            Text(image.isDangling ? "This can't be undone." : "Pull it again to get it back; images you built locally are gone for good.")
        }
        .overlay(alignment: .bottom) {
            if let error = images.errorMessage, !images.images.isEmpty {
                ErrorBanner(message: error) { images.errorMessage = nil }
                    .padding(.bottom, 16)
            } else if let toast = images.toast {
                ToastView(message: toast).padding(.bottom, 20)
            }
        }
        .animation(.easeOut(duration: 0.2), value: images.toast)
    }

    static func title(_ image: DockerImage) -> String {
        image.isDangling ? image.shortID : image.reference
    }
}

/// Title + subtitle, spacer, refresh/sort capsule, search capsule, Pull image.
private struct ImagesHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var images = model.images
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Images").font(.ui(15, .semibold))
                Text(verbatim: images.summary)
                    .font(.ui(11))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.trailing, 6)

            Spacer(minLength: 10)

            GlassCapsule {
                Button { Task { await images.refresh() } } label: {
                    Label { Text("Refresh") } icon: { LineIcon(kind: .refresh).icon(Palette.text, size: 16) }
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")

                Menu {
                    Picker("Sort by", selection: $images.sort) {
                        ForEach(ImageSort.allCases) { Text($0.rawValue).tag($0) }
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
                .help("Sort by creation date, repository or size")
                .accessibilityLabel("Sort")
            }

            HStack(spacing: 6) {
                LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                TextField("Search", text: $images.searchText)
                    .textFieldStyle(.plain)
                    .font(.ui(13))
            }
            .padding(.horizontal, 12)
            .frame(width: 200, height: 34)
            .glassSurface(Capsule())
            .help("Search by repository, tag or ID")

            Button { images.openPull() } label: {
                HStack(spacing: 6) {
                    LineIcon(kind: .download).icon(.white, size: 14, svgStrokeWidth: 2.2)
                    Text("Pull image")
                }
            }
            .buttonStyle(TintButtonStyle())
            .keyboardShortcut("n")
            .help("Download an image from a registry (⌘N)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }
}

/// Glass bar: "Image" field, progress, Cancel, Pull.
/// PullImageModal.dc.html: the reference, then the download's progress. Closing it leaves the pull running.
struct PullImageModal: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var images = model.images
        ModalPanel(title: "Pull an image", lede: "From Docker Hub, or any registry as host/name:tag", width: 520) {
            ModalTextField(label: "Image", placeholder: "nginx:latest", text: $images.pullReference) {
                Task { await images.pull() }
            }
            .disabled(images.isPulling)
            if let progress = images.pullProgress {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: progress.title)
                        .font(.ui(12, .semibold))
                        .monospacedDigit()
                    ProgressBar(fraction: progress.fraction)
                    Text("You can close this; the pull keeps going.")
                        .font(.ui(11))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.field, in: .rect(cornerRadius: 14))
            } else if let error = images.pullError {
                Text(error).font(.ui(11)).foregroundStyle(Palette.danger)
            }
        } actions: {
            Button("Cancel") { images.cancelPull() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help(images.isPulling ? "Stop downloading" : "Close")
            Button("Pull") { Task { await images.pull() } }
                .buttonStyle(TintButtonStyle())
                .disabled(images.isPulling || images.pullReference.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

/// 6 pt track with the `#0066CC` fill; indeterminate before sizes are known.
struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        if let fraction {
            Capsule()
                .fill(Palette.progressTrack)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(Palette.accent).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 6)
                .animation(.linear(duration: 0.2), value: fraction)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }
}

/// `grid-template-columns: 2.4fr 1.2fr 1.3fr 1fr 0.9fr 1.6fr 84px; gap: 12px; padding: 0 16px`.
private struct ImageColumns {
    static let actions: CGFloat = 84
    static let gap: CGFloat = 12
    static let padding: CGFloat = 16

    let repository, tag, id, created, size, usedBy: CGFloat

    init(width: CGFloat) {
        let fractions = max(width - 2 * Self.padding - Self.actions - 6 * Self.gap, 0)
        let fr = fractions / 8.4
        repository = 2.4 * fr
        tag = 1.2 * fr
        id = 1.3 * fr
        created = 1 * fr
        size = 0.9 * fr
        usedBy = 1.6 * fr
    }
}

private struct ImagesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let images = model.images
        GeometryReader { geometry in
            let columns = ImageColumns(width: geometry.size.width)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ImagesHeaderRow(columns: columns)
                    ForEach(images.visibleImages) { image in
                        ImageRow(image: image, columns: columns)
                    }
                }
                .frame(width: geometry.size.width)
                .cardSurface()
                .clipShape(.rect(cornerRadius: 14))
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .defaultScrollAnchor(.top)
        }
    }
}

private struct ImagesHeaderRow: View {
    let columns: ImageColumns

    var body: some View {
        HStack(spacing: ImageColumns.gap) {
            Text("REPOSITORY").frame(width: columns.repository, alignment: .leading)
            Text("TAG").frame(width: columns.tag, alignment: .leading)
            Text("IMAGE ID").frame(width: columns.id, alignment: .leading)
            Text("CREATED").frame(width: columns.created, alignment: .leading)
            Text("SIZE").frame(width: columns.size, alignment: .trailing)
            Text("USED BY").frame(width: columns.usedBy, alignment: .leading)
            Text("ACTIONS").frame(width: ImageColumns.actions, alignment: .center)
        }
        .font(.ui(11, .semibold))
        .tracking(0.33)
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, ImageColumns.padding)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }
    }
}

private struct ImageRow: View {
    @Environment(AppModel.self) private var model
    let image: DockerImage
    let columns: ImageColumns

    var body: some View {
        let images = model.images
        let usedBy = images.usedBy(image)
        Hoverable { hovered in
            HStack(spacing: ImageColumns.gap) {
                Text(image.repository)
                    .font(.ui(13, .medium))
                    .foregroundStyle(image.isDangling ? Palette.secondary : Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: columns.repository, alignment: .leading)

                Text(image.tag)
                    .font(.mono(12))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .frame(width: columns.tag, alignment: .leading)

                Text(image.shortID)
                    .font(.mono(11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .frame(width: columns.id, alignment: .leading)
                    .help(image.imageID)

                Text(ImageAge.text(for: image.created))
                    .font(.ui(12))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .frame(width: columns.created, alignment: .leading)
                    .help(image.created.formatted(date: .abbreviated, time: .shortened))

                Text(ByteFormat.short(image.size))
                    .font(.ui(12))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: columns.size, alignment: .trailing)

                UsedByLabel(image: image, usedBy: usedBy)
                    .frame(width: columns.usedBy, alignment: .leading)

                ImageActions(image: image, canRemove: usedBy.isEmpty)
                    .frame(width: ImageColumns.actions, alignment: .center)
            }
            .padding(.horizontal, ImageColumns.padding)
            .frame(height: 48)
            .background(hovered ? Palette.rowHover : .clear)
            .overlay(alignment: .bottom) { Palette.rowDivider.frame(height: 1) }
            .contentShape(.rect)
        }
        .contextMenu {
            Button("Run Container…") { model.openRunForm(image: image.isDangling ? image.imageID : image.reference) }
            Button("Copy Image ID") {
                Clipboard.copy(image.imageID)
            }
            Divider()
            Button("Remove…", role: .destructive) { images.pendingRemoval = image }
                .disabled(!usedBy.isEmpty)
        }
    }
}

private struct UsedByLabel: View {
    let image: DockerImage
    let usedBy: [String]

    var body: some View {
        let (text, color, dot): (String, Color, Color) = if !usedBy.isEmpty {
            (usedBy.joined(separator: ", "), Palette.greenText, Palette.greenDot)
        } else if image.isDangling {
            ("Dangling", Palette.orangeText, Palette.orangeDot)
        } else {
            ("Unused", Palette.secondary, Palette.grayDot)
        }
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.ui(12))
        .foregroundStyle(color)
        .help(usedBy.isEmpty ? "No container uses this image" : "Used by \(usedBy.joined(separator: ", "))")
    }
}

private struct ImageActions: View {
    @Environment(AppModel.self) private var model
    let image: DockerImage
    let canRemove: Bool

    var body: some View {
        let images = model.images
        HStack(spacing: 2) {
            if images.removingIDs.contains(image.id) {
                ProgressView().controlSize(.small).frame(width: 58, height: 28)
            } else {
                Button { model.openRunForm(image: image.isDangling ? image.imageID : image.reference) } label: {
                    Label { Text("Run") } icon: { PlayShape().fill(Palette.greenText).frame(width: 14, height: 14) }
                }
                .help("Run a container from \(ImagesView.title(image))")

                Button { images.pendingRemoval = image } label: {
                    Label { Text("Remove") } icon: { LineIcon(kind: .trash).icon(Palette.danger, size: 14) }
                }
                .disabled(!canRemove)
                .opacity(canRemove ? 1 : 0.35)
                .help(canRemove ? "Remove \(ImagesView.title(image))…" : "In use — remove its containers first")
            }
        }
        .buttonStyle(ToolbarIconButtonStyle(width: 28))
    }
}
