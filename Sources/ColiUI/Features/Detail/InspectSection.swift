import AppKit
import SwiftUI

/// Inspect.dc.html: filter, Tree / Raw, Expand all, Collapse all, Copy JSON; the tree card or raw panel; footer.
struct InspectSection: View {
    let inspect: InspectViewModel

    var body: some View {
        @Bindable var inspect = inspect
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                    TextField("Filter keys and values", text: $inspect.filter)
                        .textFieldStyle(.plain)
                        .font(.ui(13))
                }
                .padding(.horizontal, 12)
                .frame(minWidth: 180, maxWidth: .infinity)
                .frame(height: 34)
                .background(Palette.field, in: .capsule)

                ModeSegments(selection: $inspect.mode)

                Button("Expand all") { inspect.expandAll() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(inspect.mode == .raw)
                Button("Collapse all") { inspect.collapseAll() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(inspect.mode == .raw)
                Button { Clipboard.copy(inspect.rawJSON) } label: {
                    HStack(spacing: 6) {
                        LineIcon(kind: .copy).icon(Palette.text, size: 13)
                        Text("Copy JSON")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(inspect.rawJSON.isEmpty)
                .help("Copy the JSON, secrets masked")
            }

            Group {
                switch inspect.state {
                case .idle, .loading:
                    MessageCard("Loading…")
                case .failed(let error):
                    MessageCard(error, color: Palette.danger)
                case .loaded:
                    if inspect.mode == .tree { tree } else { raw }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Same JSON as \(Text("docker inspect").font(.mono(12))) · secrets in \(Text("Env").font(.mono(12))) are masked · click a value to copy it")
                .font(.ui(12))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var tree: some View {
        let rows = inspect.rows
        // Vertical only: a lazy stack in a two-axis scroll view sizes its width from the visible rows
        // and lands off to the side. Long values truncate instead (tooltip and click-to-copy keep them whole).
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    TreeRow(row: row, toggle: { inspect.toggle(row) }, copy: Clipboard.copy)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if rows.isEmpty {
                Text("No keys or values match “\(inspect.filter)”.")
                    .font(.ui(13))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .cardSurface()
        .accessibilityLabel("docker inspect")
    }

    private var raw: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(verbatim: inspect.rawJSON)
                .font(.mono(12))
                .lineSpacing(4)
                .foregroundStyle(Palette.logText)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.topLeading)
        .background(Palette.logBackground, in: .rect(cornerRadius: 14))
        // Dark scrollers on the dark panel; otherwise the corner where both scroll bars meet stays white.
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("docker inspect JSON")
    }
}

/// `.row`: 24 pt, 18 pt indent per level, disclosure triangle, key, value colored by type.
private struct TreeRow: View {
    let row: InspectRow
    let toggle: () -> Void
    let copy: (String) -> Void

    var body: some View {
        Hoverable { hovered in
            HStack(spacing: 6) {
                if row.isBranch {
                    Button(action: toggle) {
                        Disclosure()
                            .fill(Palette.jsonPunctuation)
                            .frame(width: 10, height: 10)
                            .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                            .frame(width: 16, height: 16)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.isExpanded ? "Collapse \(row.key ?? "root")" : "Expand \(row.key ?? "root")")
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
                if let key = row.key {
                    Text("\(Text(verbatim: key).foregroundStyle(Palette.jsonKey))\(Text(verbatim: ": ").foregroundStyle(Palette.jsonPunctuation))")
                        .fixedSize()
                }
                if let copyText = row.copyText {
                    Button { copy(copyText) } label: {
                        Text(verbatim: row.value).foregroundStyle(color).truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                    .help(copyText.count > 80 ? "\(copyText)\n\nClick to copy" : "Copy value")
                } else if !row.value.isEmpty {
                    Text(verbatim: row.value).foregroundStyle(Palette.jsonPunctuation)
                }
                if !row.summary.isEmpty {
                    Text(verbatim: row.summary).foregroundStyle(Palette.jsonSummary)
                }
            }
            .font(.mono(12))
            .lineLimit(1)
            .padding(.leading, CGFloat(row.depth * 18 + 4))
            .padding(.trailing, 12)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Palette.jsonRowHover : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture { if row.isBranch { toggle() } }
        }
    }

    private var color: Color {
        switch row.kind {
        case .string: Palette.jsonString
        case .number: Palette.jsonNumber
        case .bool: Palette.jsonBool
        default: Palette.jsonPunctuation
        }
    }
}

/// `M8 5l10 7-10 7z`: the right-pointing disclosure triangle.
private struct Disclosure: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: 8 * scale, y: 5 * scale))
        path.addLine(to: CGPoint(x: 18 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 8 * scale, y: 19 * scale))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Tree / Raw: `.seg` buttons in a plain field capsule (not glass).
private struct ModeSegments: View {
    @Binding var selection: InspectViewModel.Mode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InspectViewModel.Mode.allCases) { mode in
                let isOn = mode == selection
                Button { selection = mode } label: {
                    Hoverable { hovered in
                        Text(mode.rawValue)
                            .font(.ui(12, isOn ? .semibold : .regular))
                            .foregroundStyle(isOn || hovered ? Palette.segmentOnText : Palette.segmentOffText)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background {
                                if isOn { Capsule().fill(Palette.segmentOn).shadow(color: .black.opacity(0.14), radius: 2, y: 1) }
                            }
                            .contentShape(.capsule)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 34)
        .background(Palette.field, in: .capsule)
    }
}
