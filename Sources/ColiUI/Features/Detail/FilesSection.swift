import AppKit
import ColiUICore
import SwiftUI
import UniformTypeIdentifiers

/// Files.dc.html: navigation capsule, path segments, filter, Hidden files; the folder table and the preview panel.
struct FilesSection: View {
    let files: FilesViewModel
    let container: Container?
    let shellHere: (String) -> Void

    var body: some View {
        @Bindable var files = files
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GlassCapsule {
                    Button { Task { await files.goBack() } } label: {
                        LineIcon(kind: .chevronLeft).icon(Palette.text, size: 15, svgStrokeWidth: 2.2)
                    }
                    .buttonStyle(ToolbarIconButtonStyle(width: 30))
                    .disabled(!files.canGoBack)
                    .opacity(files.canGoBack ? 1 : 0.35)
                    .accessibilityLabel("Back")
                    Button { Task { await files.goUp() } } label: {
                        LineIcon(kind: .arrowUp).icon(Palette.text, size: 15, svgStrokeWidth: 2.2)
                    }
                    .buttonStyle(ToolbarIconButtonStyle(width: 30))
                    .disabled(!files.canGoUp)
                    .opacity(files.canGoUp ? 1 : 0.35)
                    .accessibilityLabel("Enclosing folder")
                    Button { Task { await files.refresh() } } label: {
                        LineIcon(kind: .refresh).icon(Palette.text, size: 14, svgStrokeWidth: 2.2)
                    }
                    .buttonStyle(ToolbarIconButtonStyle(width: 30))
                    .accessibilityLabel("Refresh")
                }

                PathCrumbs(files: files)

                HStack(spacing: 6) {
                    LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                    TextField("Filter this folder", text: $files.filter)
                        .textFieldStyle(.plain)
                        .font(.ui(13))
                }
                .padding(.horizontal, 12)
                .frame(width: 200, height: 34)
                .background(Palette.field, in: .capsule)

                Button("Hidden files") { files.showHidden.toggle() }
                    .buttonStyle(PillButtonStyle(isOn: files.showHidden))
                    .accessibilityAddTraits(files.showHidden ? .isSelected : [])
            }

            if let notice = files.notice {
                Text(notice).font(.ui(12)).foregroundStyle(Palette.danger)
            }

            Group {
                if !(container?.isRunning ?? false) {
                    message("Start \(container?.name ?? "the container") to browse its files.")
                } else {
                    switch files.state {
                    case .idle, .loading: message("Loading…")
                    case .failed(let error): message(error, color: Palette.danger)
                    case .loaded:
                        HStack(alignment: .top, spacing: 14) {
                            FolderTable(files: files)
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                            PreviewPanel(files: files, shellHere: shellHere)
                                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380, maxHeight: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Read-only · double-click a folder to open it · lists with \(Text("docker exec").font(.mono(12))), downloads through the archive API · previews show the first 256 KB of text files")
                .font(.ui(12))
                .foregroundStyle(Palette.secondary)
        }
    }

    private func message(_ text: String, color: Color = Palette.secondary) -> some View {
        Text(text)
            .font(.ui(13))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }
}

/// `/ app src`: each segment opens that folder; the current one is semibold.
private struct PathCrumbs: View {
    let files: FilesViewModel

    var body: some View {
        let parts = files.crumbs
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                crumb("/", target: "/", isCurrent: parts.isEmpty)
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 { Text("/").font(.mono(12)).foregroundStyle(Palette.jsonSummary).padding(.horizontal, 1) }
                    crumb(part, target: "/" + parts.prefix(index + 1).joined(separator: "/"), isCurrent: index == parts.count - 1)
                }
            }
            .padding(.horizontal, 8)
        }
        .defaultScrollAnchor(.trailing)
        .frame(minWidth: 220, maxWidth: .infinity)
        .frame(height: 34)
        .background(Palette.field, in: .capsule)
        .accessibilityLabel("Path \(files.path)")
    }

    private func crumb(_ title: String, target: String, isCurrent: Bool) -> some View {
        Button { Task { await files.go(to: target) } } label: {
            Hoverable { hovered in
                Text(verbatim: title)
                    .font(.mono(12, isCurrent ? .semibold : .regular))
                    .foregroundStyle(hovered ? Palette.text : Palette.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(hovered ? Palette.hover : .clear, in: .rect(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
    }
}

/// `grid-template-columns: 1fr 80px 128px 96px`: NAME / SIZE / MODIFIED / MODE, then the item count.
private struct FolderTable: View {
    let files: FilesViewModel

    var body: some View {
        let entries = files.visibleEntries
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                Text("SIZE").frame(width: 80, alignment: .trailing)
                Text("MODIFIED").frame(width: 128, alignment: .leading)
                Text("MODE").frame(width: 96, alignment: .leading)
            }
            .font(.ui(11, .semibold))
            .tracking(0.33)
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        FileRow(entry: entry, isSelected: files.selected?.name == entry.name,
                                select: { Task { await files.select(entry) } },
                                open: { Task { await files.open(entry) } })
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    Text(files.filter.isEmpty ? "This folder is empty." : "Nothing here matches “\(files.filter)”.")
                        .font(.ui(13))
                        .foregroundStyle(Palette.secondary)
                }
            }

            Text(files.summary)
                .font(.ui(11))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .overlay(alignment: .top) { Palette.headerDivider.frame(height: 1) }
        }
        .background(Palette.card, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }
}

private struct FileRow: View {
    let entry: ContainerFile
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void

    var body: some View {
        Hoverable { hovered in
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    FileIcon(kind: entry.kind)
                    Text(verbatim: entry.name)
                        .font(.ui(13))
                        .foregroundStyle(entry.isHidden ? Palette.secondary : Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let target = entry.linkTarget {
                        Text(verbatim: "→ \(target)").font(.ui(11)).foregroundStyle(Palette.jsonPunctuation).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(FileFormat.size(entry)).frame(width: 80, alignment: .trailing)
                Text(FileFormat.date(entry.modified)).frame(width: 128, alignment: .leading)
                Text(verbatim: entry.mode).font(.mono(12)).frame(width: 96, alignment: .leading)
            }
            .font(.ui(12))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(isSelected ? Palette.rowSelected : hovered ? Palette.rowHover : .clear)
            .overlay(alignment: .bottom) { Palette.rowDivider.frame(height: 1) }
            .contentShape(.rect)
            .onTapGesture(count: 2, perform: open)
            .onTapGesture(perform: select)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: entry.kind == .directory ? "Open" : "Select", entry.kind == .directory ? open : select)
    }
}

/// Folder (filled blue), file (page with a folded corner) or link.
private struct FileIcon: View {
    let kind: ContainerFile.Kind

    var body: some View {
        switch kind {
        case .directory:
            FolderShape().fill(Color(red: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255))
                .overlay(FolderShape().stroke(Color(red: 0x3B / 255, green: 0xA9 / 255, blue: 0xDB / 255), lineWidth: 0.7))
                .frame(width: 16, height: 16)
        case .symlink:
            LineIcon(kind: .link).icon(Palette.jsonPunctuation, size: 16)
        default:
            PageShape().fill(Palette.card)
                .overlay(PageShape().stroke(Palette.jsonPunctuation, lineWidth: 1.1))
                .frame(width: 16, height: 16)
        }
    }
}

/// `M3 6.5A1.5 1.5 0 0 1 4.5 5h4.6l2 2h8.4A1.5 1.5 0 0 1 21 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z`
private struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: 3 * s, y: 6.5 * s))
        path.addQuadCurve(to: CGPoint(x: 4.5 * s, y: 5 * s), control: CGPoint(x: 3 * s, y: 5 * s))
        path.addLine(to: CGPoint(x: 9.1 * s, y: 5 * s))
        path.addLine(to: CGPoint(x: 11.1 * s, y: 7 * s))
        path.addLine(to: CGPoint(x: 19.5 * s, y: 7 * s))
        path.addQuadCurve(to: CGPoint(x: 21 * s, y: 8.5 * s), control: CGPoint(x: 21 * s, y: 7 * s))
        path.addLine(to: CGPoint(x: 21 * s, y: 17.5 * s))
        path.addQuadCurve(to: CGPoint(x: 19.5 * s, y: 19 * s), control: CGPoint(x: 21 * s, y: 19 * s))
        path.addLine(to: CGPoint(x: 4.5 * s, y: 19 * s))
        path.addQuadCurve(to: CGPoint(x: 3 * s, y: 17.5 * s), control: CGPoint(x: 3 * s, y: 19 * s))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// `M6 3h8l4 4v14H6z` plus the fold `M14 3v4h4`.
private struct PageShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: 6 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 14 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 7 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 21 * s))
        path.addLine(to: CGPoint(x: 6 * s, y: 21 * s))
        path.closeSubpath()
        path.move(to: CGPoint(x: 14 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 14 * s, y: 7 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 7 * s))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The selected entry (or the folder shown): details, actions, and the text contents.
private struct PreviewPanel: View {
    let files: FilesViewModel
    let shellHere: (String) -> Void

    var body: some View {
        let entry = files.selected
        let folderName = files.crumbs.last ?? "/"
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: entry?.name ?? folderName)
                    .font(.mono(14, .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    detail("Kind", kind(entry))
                    detail("Size", entry.map(FileFormat.size) ?? "\(files.visibleEntries.count) items")
                    detail("Modified", entry.map { FileFormat.date($0.modified) } ?? "—")
                    detail("Mode", entry?.mode ?? "—")
                    detail("Owner", entry?.owner ?? "—")
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    Button { download() } label: {
                        HStack(spacing: 6) {
                            LineIcon(kind: .download).icon(Palette.text, size: 13)
                            Text(entry?.kind == .file ? "Download…" : "Download folder…")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(entry?.kind == .symlink || entry?.kind == .other)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(files.selectedPath ?? files.path, forType: .string)
                    } label: {
                        HStack(spacing: 6) {
                            LineIcon(kind: .copy).icon(Palette.text, size: 13)
                            Text("Copy path")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    Button { shellHere(files.shellFolder) } label: {
                        HStack(spacing: 6) {
                            LineIcon(kind: .terminal).icon(Palette.text, size: 13)
                            Text("Shell here")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("Open the Terminal tab in \(files.shellFolder)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }

            content(entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.card, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func content(_ entry: ContainerFile?) -> some View {
        switch files.preview {
        case .text(let text):
            ScrollView([.vertical, .horizontal]) {
                Text(verbatim: text)
                    .font(.mono(11.5))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.logText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(Palette.logBackground)
        case .loading: note("Loading…")
        case .binary: note("This file isn't text, so it can't be previewed. Download it instead.")
        case .tooLarge: note("Too large to preview (over 256 KB). Download it instead.")
        case .failed(let error): note(error, color: Palette.danger)
        case .none:
            switch entry?.kind {
            case nil: note("Select a file to preview it.")
            case .directory?: note("Double-click to open this folder.")
            case .symlink?: note("Links point elsewhere in the container. Double-click to follow it.")
            default: note("This entry can't be previewed.")
            }
        }
    }

    private func note(_ text: String, color: Color = Palette.secondary) -> some View {
        Text(text)
            .font(.ui(12))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detail(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key).font(.ui(11)).foregroundStyle(Palette.secondary)
            Text(verbatim: value)
                .font(.mono(12))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func kind(_ entry: ContainerFile?) -> String {
        switch entry?.kind {
        case nil, .directory?: "Folder"
        case .file?: "File"
        case .symlink?: "Symlink → \(entry?.linkTarget ?? "?")"
        case .other?: "Other"
        }
    }

    /// Fetches through the archive API, then asks where to save it.
    private func download() {
        Task {
            do {
                let (filename, data) = try await files.download()
                let panel = NSSavePanel()
                panel.nameFieldStringValue = filename
                if filename.hasSuffix(".tar") { panel.allowedContentTypes = [UTType(filenameExtension: "tar") ?? .data] }
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url)
            } catch {
                NSSound.beep()
            }
        }
    }
}

enum FileFormat {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()

    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }

    static func size(_ entry: ContainerFile) -> String {
        entry.kind == .file ? ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file) : "—"
    }
}
