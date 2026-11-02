import AppKit
import ColiUICore
import SwiftUI

/// Environment.dc.html: filter, source segments, Show secrets, Copy as .env; the variables table; footer.
struct EnvironmentSection: View {
    let environment: EnvironmentViewModel

    var body: some View {
        @Bindable var environment = environment
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                    TextField("Filter variables", text: $environment.filter)
                        .textFieldStyle(.plain)
                        .font(.ui(13))
                }
                .padding(.horizontal, 12)
                .frame(minWidth: 180, maxWidth: .infinity)
                .frame(height: 34)
                .background(Palette.field, in: .capsule)

                ScopeSegments(environment: environment)

                Button { environment.revealAll.toggle() } label: {
                    HStack(spacing: 6) {
                        LineIcon(kind: .eye).icon(environment.revealAll ? Palette.toggleOnText : Palette.text, size: 14)
                        Text(environment.revealAll ? "Hide secrets" : "Show secrets")
                    }
                }
                .buttonStyle(PillButtonStyle(isOn: environment.revealAll))
                .accessibilityAddTraits(environment.revealAll ? .isSelected : [])

                Button { Clipboard.copy(environment.dotEnv) } label: {
                    HStack(spacing: 6) {
                        LineIcon(kind: .copy).icon(Palette.text, size: 13)
                        Text("Copy as .env")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(environment.rows.isEmpty)
                .help("Copy the rows shown as NAME=value lines; masked secrets stay masked")
            }

            Group {
                switch environment.state {
                case .idle, .loading: message("Loading…")
                case .failed(let error): message(error, color: Palette.danger)
                case .loaded: table
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                LineIcon(kind: .lock).icon(Palette.secondary, size: 12, svgStrokeWidth: 2.2)
                Text("\(environment.footnote) · read-only: changing a variable means recreating the container")
            }
            .font(.ui(12))
            .foregroundStyle(Palette.secondary)
        }
        .onDisappear { environment.hideSecrets() }
    }

    private var table: some View {
        let rows = environment.rows
        return VStack(spacing: 0) {
            ColumnsRow {
                Text("NAME")
            } value: {
                Text("VALUE")
            } source: {
                Text("SOURCE")
            } copy: {
                Text("COPY")
            }
            .font(.ui(11, .semibold))
            .tracking(0.33)
            .foregroundStyle(Palette.secondary)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        VariableRow(row: row, toggle: { environment.toggleReveal(row.name) }, copy: Clipboard.copy)
                    }
                }
            }
            .overlay {
                if rows.isEmpty {
                    Text(environment.filter.isEmpty ? "No variables." : "No variables match “\(environment.filter)”.")
                        .font(.ui(13))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .background(Palette.card, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    private func message(_ text: String, color: Color = Palette.secondary) -> some View {
        Text(text)
            .font(.ui(13))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }
}

/// `grid-template-columns: 1.3fr 2.6fr 96px 64px; gap: 12px; padding: 0 16px`.
private struct ColumnsRow<Name: View, Value: View, Source: View, Copy: View>: View {
    @ViewBuilder let name: Name
    @ViewBuilder let value: Value
    @ViewBuilder let source: Source
    @ViewBuilder let copy: Copy

    var body: some View {
        GeometryReader { proxy in
            let flexible = max(proxy.size.width - 32 - 96 - 64 - 36, 0)
            HStack(spacing: 12) {
                name.frame(width: flexible * 1.3 / 3.9, alignment: .leading)
                value.frame(width: flexible * 2.6 / 3.9, alignment: .leading)
                source.frame(width: 96, alignment: .leading)
                copy.frame(width: 64, alignment: .center)
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct VariableRow: View {
    let row: EnvironmentRow
    let toggle: () -> Void
    let copy: (String) -> Void

    var body: some View {
        Hoverable { hovered in
            ColumnsRow {
                Text(verbatim: row.name)
                    .font(.mono(12, .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(row.name)
            } value: {
                HStack(spacing: 6) {
                    Text(verbatim: row.shownValue)
                        .font(.mono(12))
                        .foregroundStyle(row.isRevealed ? Palette.tertiary : Palette.jsonPunctuation)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.isRevealed ? row.shownValue : "")
                    if row.isSecret {
                        Button(action: toggle) {
                            LineIcon(kind: .eye).icon(Palette.secondary, size: 14)
                        }
                        .buttonStyle(ToolbarIconButtonStyle(width: 26))
                        .frame(height: 22)
                        .accessibilityLabel((row.isRevealed ? "Hide " : "Show ") + row.name)
                    }
                }
            } source: {
                SourceChip(source: row.source)
            } copy: {
                Button { copy(row.value) } label: {
                    LineIcon(kind: .copy).icon(Palette.text, size: 14)
                }
                .buttonStyle(ToolbarIconButtonStyle(width: 28))
                .accessibilityLabel("Copy \(row.name)")
                .help("Copy the value")
            }
            .frame(height: 40)
            .background(hovered ? Palette.rowHover : .clear)
            .overlay(alignment: .bottom) { Palette.rowDivider.frame(height: 1) }
        }
    }
}

/// `.chip`: blue "Container", gray "Image".
private struct SourceChip: View {
    let source: EnvironmentEntry.Source

    var body: some View {
        let isContainer = source == .container
        Text(isContainer ? "Container" : "Image")
            .font(.ui(11))
            .foregroundStyle(isContainer ? Palette.toggleOnText : Palette.tertiary)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(isContainer ? Palette.toggleOn : Palette.chip, in: .capsule)
    }
}

/// All / Container / Image with counts: `.seg` buttons in a plain field capsule.
private struct ScopeSegments: View {
    let environment: EnvironmentViewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EnvironmentViewModel.Scope.allCases) { scope in
                let isOn = scope == environment.scope
                Button { environment.scope = scope } label: {
                    Hoverable { hovered in
                        Text("\(scope.rawValue) (\(environment.count(of: scope)))")
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

