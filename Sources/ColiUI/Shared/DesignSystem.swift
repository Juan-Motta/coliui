import AppKit
import SwiftUI

/// Exact tokens from the Liquid Glass designs (Main.dc.html / DarkMode.dc.html / Sidebar.dc.html).
enum Palette {
    static let window = dynamic(rgb(0xFB, 0xFB, 0xFD), rgb(0x1C, 0x1C, 0x1E))
    static let sidebar = dynamic(rgb(240, 240, 244, 0.72), rgb(48, 48, 52, 0.72))
    static let glass = dynamic(rgb(255, 255, 255, 0.6), rgb(44, 44, 48, 0.6))
    static let glassBorder = dynamic(rgb(255, 255, 255, 0.8), rgb(255, 255, 255, 0.12))
    static let glassHighlight = dynamic(rgb(255, 255, 255, 0.7), rgb(255, 255, 255, 0.08))
    static let glassShadow = dynamic(rgb(0, 0, 0, 0.08), rgb(0, 0, 0, 0.3))

    static let text = dynamic(rgb(0x1D, 0x1D, 0x1F), rgb(0xF5, 0xF5, 0xF7))
    static let secondary = dynamic(rgb(0x6E, 0x6E, 0x73), rgb(0xAE, 0xAE, 0xB2))
    static let sidebarSecondary = dynamic(rgb(0x5E, 0x5E, 0x63), rgb(0xAE, 0xAE, 0xB2))
    static let tertiary = dynamic(rgb(0x3A, 0x3A, 0x3C), rgb(0xD1, 0xD1, 0xD6))

    static let colimaCard = dynamic(rgb(0, 0, 0, 0.04), rgb(255, 255, 255, 0.08))
    static let colimaButton = dynamic(.white, rgb(255, 255, 255, 0.12))
    static let chip = dynamic(rgb(0, 0, 0, 0.06), rgb(255, 255, 255, 0.12))
    static let selected = dynamic(rgb(0, 102, 204, 0.14), rgb(77, 163, 255, 0.24))
    static let accent = dynamic(rgb(0x00, 0x66, 0xCC), rgb(0x4D, 0xA3, 0xFF))
    static let segmentOn = dynamic(.white, rgb(0x63, 0x63, 0x66))
    static let segmentOnText = dynamic(rgb(0x1D, 0x1D, 0x1F), .white)
    static let segmentOffText = dynamic(rgb(0x3A, 0x3A, 0x3C), rgb(0xD1, 0xD1, 0xD6))
    static let tint = dynamic(rgb(0x0A, 0x6F, 0xD6), rgb(0x0A, 0x84, 0xFF))
    static let tintHover = dynamic(rgb(0x08, 0x62, 0xBF), rgb(0x00, 0x77, 0xED))
    /// `.ib:hover` / `.nav:hover` washes.
    static let hover = dynamic(rgb(0, 0, 0, 0.06), rgb(255, 255, 255, 0.1))
    static let hoverSubtle = dynamic(rgb(0, 0, 0, 0.05), rgb(255, 255, 255, 0.08))
    static let tintShadow = dynamic(rgb(0, 102, 204, 0.3), rgb(10, 132, 255, 0.35))

    static let card = dynamic(.white, rgb(0x23, 0x23, 0x26))
    static let cardBorder = dynamic(rgb(0, 0, 0, 0.08), rgb(255, 255, 255, 0.08))
    static let headerDivider = dynamic(rgb(0, 0, 0, 0.06), rgb(255, 255, 255, 0.06))
    static let rowDivider = dynamic(rgb(0, 0, 0, 0.04), rgb(255, 255, 255, 0.04))
    static let rowHover = dynamic(rgb(0, 102, 204, 0.05), rgb(77, 163, 255, 0.14))

    /// `.pill` / logs filter field fill and its hover.
    static let field = dynamic(rgb(0, 0, 0, 0.05), rgb(255, 255, 255, 0.08))
    static let fieldHover = dynamic(rgb(0, 0, 0, 0.09), rgb(255, 255, 255, 0.14))
    static let toggleOn = dynamic(rgb(0, 102, 204, 0.14), rgb(77, 163, 255, 0.24))
    static let toggleOnText = dynamic(rgb(0x0B, 0x4F, 0x8A), rgb(0x7B, 0xBB, 0xFF))
    static let greenPill = dynamic(rgb(0xE7, 0xF6, 0xEC), rgb(48, 209, 88, 0.16))
    static let orangePill = dynamic(rgb(0xFE, 0xF3, 0xE7), rgb(255, 159, 10, 0.16))

    /// Selected row in a card list (profiles).
    static let rowSelected = dynamic(rgb(0, 102, 204, 0.10), rgb(77, 163, 255, 0.18))

    /// Cleanup option cards when selected.
    static let optionSelected = dynamic(rgb(0xF6, 0xF9, 0xFE), rgb(77, 163, 255, 0.1))
    static let optionSelectedBorder = dynamic(rgb(0, 102, 204, 0.4), rgb(77, 163, 255, 0.45))
    static let destructive = dynamic(rgb(0xC4, 0x32, 0x0A), rgb(0xE0, 0x45, 0x1A))
    /// Disk bar segments: images, build cache, volumes, containers.
    static let diskImages = Color(nsColor: rgb(0x00, 0x66, 0xCC))
    static let diskCache = Color(nsColor: rgb(0xC2, 0x41, 0x0C))
    static let diskVolumes = Color(nsColor: rgb(0x7C, 0x5C, 0xD6))
    static let diskContainers = Color(nsColor: rgb(0x1E, 0x7F, 0x3C))

    /// Log panel (same in light and dark).
    static let logBackground = Color(nsColor: rgb(0x1C, 0x1C, 0x1E))
    static let logTime = Color(nsColor: rgb(0x8E, 0x8E, 0x93))
    static let logText = Color(nsColor: rgb(0xE5, 0xE5, 0xEA))
    static let logInfo = Color(nsColor: rgb(0x64, 0xD2, 0xFF))
    static let logWarn = Color(nsColor: rgb(0xFF, 0xD6, 0x0A))
    static let logError = Color(nsColor: rgb(0xFF, 0x69, 0x61))

    static let greenText = dynamic(rgb(0x1E, 0x7F, 0x3C), rgb(0x4C, 0xD9, 0x64))
    static let greenDot = dynamic(rgb(0x28, 0xC8, 0x40), rgb(0x30, 0xD1, 0x58))
    static let orangeText = dynamic(rgb(0xB5, 0x47, 0x08), rgb(0xFF, 0xB3, 0x40))
    static let orangeDot = dynamic(rgb(0xE8, 0x59, 0x0C), rgb(0xFF, 0x9F, 0x0A))
    static let grayDot = dynamic(rgb(0xAE, 0xAE, 0xB2), rgb(0x8E, 0x8E, 0x93))
    static let danger = dynamic(rgb(0xB4, 0x23, 0x18), rgb(0xFF, 0x69, 0x61))

    private static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension Font {
    /// SF Pro at the exact pixel size used in the designs.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// The designs' `.glass` class: translucent fill, white hairline, inset top highlight, soft drop shadow.
    func glassSurface<S: InsettableShape>(_ shape: S, fill: Color = Palette.glass) -> some View {
        background(fill, in: shape)
            .overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 1))
            .overlay(
                shape.inset(by: 1).stroke(
                    LinearGradient(colors: [Palette.glassHighlight, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.12)),
                    lineWidth: 1
                )
            )
            .shadow(color: Palette.glassShadow, radius: 8, y: 4)
    }
}

extension View {
    /// Same surface for shapes that can't be inset (e.g. `ConcentricRectangle`):
    /// strokes are doubled and clipped to the shape, which leaves them 1 pt inside like `strokeBorder`.
    func glassSurface<S: Shape>(_ shape: S, fill: Color = Palette.glass) -> some View {
        background {
            ZStack {
                shape.fill(fill)
                shape.stroke(
                    LinearGradient(colors: [Palette.glassHighlight, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.12)),
                    lineWidth: 4
                )
                shape.stroke(Palette.glassBorder, lineWidth: 2)
            }
            .clipShape(shape)
            .shadow(color: Palette.glassShadow, radius: 8, y: 4)
        }
    }
}

/// `.glass .cap`: 34 pt tall capsule, 3 pt inner padding, 2 pt between children.
struct GlassCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(.horizontal, 3)
            .frame(height: 34)
            .glassSurface(Capsule())
    }
}

/// Tracks pointer hover for its content.
/// `State` is a plain stored property on purpose: the `@State` attribute is a macro whose plugin
/// ships only with Xcode, but SwiftUI still recognises a stored `State` value as view state.
struct Hoverable<Content: View>: View {
    private let hovering = State(initialValue: false)
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(hovering.wrappedValue)
            .onHover { hovering.wrappedValue = $0 }
    }
}

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    /// Tooltip shown after hovering; empty shows none.
    var help: String = ""
    var id: Value { value }
}

/// `.seg` / `.on` segments inside a glass capsule.
struct CapsuleSegmented<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        GlassCapsule {
            ForEach(options) { option in
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    Hoverable { hovered in
                        Text(option.title)
                            .font(.ui(12, isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Palette.segmentOnText : Palette.segmentOffText)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background {
                                if isOn {
                                    Capsule().fill(Palette.segmentOn).shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                                } else if hovered {
                                    Capsule().fill(Palette.hoverSubtle)
                                }
                            }
                            .contentShape(.capsule)
                    }
                }
                .buttonStyle(.plain)
                .help(option.help)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// `.ib`: 34×28 icon button with a 14 pt radius hover/pressed fill.
struct ToolbarIconButtonStyle: ButtonStyle {
    var width: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .labelStyle(.iconOnly)
                .foregroundStyle(Palette.text)
                .frame(width: width, height: 28)
                .background(
                    configuration.isPressed ? Color.primary.opacity(0.12) : hovered ? Palette.hover : .clear,
                    in: .capsule
                )
                .contentShape(.capsule)
        }
    }
}

/// `.tint`: blue capsule with a white hairline and coloured shadow.
struct TintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            tinted(configuration, hovered: hovered)
        }
    }

    private func tinted(_ configuration: Configuration, hovered: Bool) -> some View {
        configuration.label
            .font(.ui(13, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background((hovered ? Palette.tintHover : Palette.tint).opacity(configuration.isPressed ? 0.88 : 1), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .overlay(Capsule().inset(by: 1).stroke(
                LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.15)),
                lineWidth: 1
            ))
            .shadow(color: Palette.tintShadow, radius: 7, y: 4)
            .contentShape(.capsule)
    }
}

/// `.pill`: 30 pt capsule, 12 pt text, soft fill that darkens on hover.
struct PillButtonStyle: ButtonStyle {
    var isOn = false
    var foreground: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.ui(12))
                .foregroundStyle(foreground ?? (isOn ? Palette.toggleOnText : Palette.text))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isOn ? Palette.toggleOn : (hovered || configuration.isPressed ? Palette.fieldHover : Palette.field), in: .capsule)
                .contentShape(.capsule)
        }
    }
}

extension View {
    /// A non-button `.pill` (holds a checkbox or a menu).
    func pillSurface() -> some View {
        font(.ui(12))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Palette.field, in: .capsule)
    }
}

/// A published port that opens in the browser: blue mono text that underlines and shows the
/// pointing-hand cursor on hover, so it reads as clickable.
struct PortLink: View {
    let title: String
    let url: URL
    var showsArrow = false

    var body: some View {
        Link(destination: url) {
            Hoverable { hovered in
                HStack(spacing: 4) {
                    Text(verbatim: title).underline(hovered)
                    if showsArrow {
                        LineIcon(kind: .external).icon(Palette.accent, size: 11, svgStrokeWidth: 2.4)
                    }
                }
                .contentShape(.rect)
            }
        }
        .foregroundStyle(Palette.accent)
        .pointerStyle(.link)
        .help("Open \(url.absoluteString) in the browser")
    }
}

/// CSS `flex-wrap: wrap` for a row of controls: children keep their natural size and move to the
/// next line when they don't fit; each line's children are centred vertically.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.midY),
                anchor: .leading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var lines: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                lines.append([])
                x = 0
            }
            lines[lines.count - 1].append((index, size))
            x += size.width + spacing
        }

        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        var maxWidth: CGFloat = 0
        for line in lines where !line.isEmpty {
            let height = line.map(\.size.height).max() ?? 0
            var x: CGFloat = 0
            for item in line {
                frames[item.index] = CGRect(x: x, y: y + (height - item.size.height) / 2, width: item.size.width, height: item.size.height)
                x += item.size.width + spacing
            }
            maxWidth = max(maxWidth, x - spacing)
            y += height + lineSpacing
        }
        return (CGSize(width: maxWidth, height: max(y - lineSpacing, 0)), frames)
    }
}

/// Line icons drawn from the designs' 24×24 SVG paths.
struct LineIcon: Shape {
    enum Kind {
        case containers, images, volumes, networks, cleanup, profiles, settings
        case refresh, sort, search, plus, trash
        case chevronLeft, chevronRight, terminal, download
        case folder, copy, external, check, warning, minus
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func line(_ points: CGPoint...) {
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
        switch kind {
        case .containers:
            line(p(12, 3), p(20, 7.5), p(20, 16.5), p(12, 21), p(4, 16.5), p(4, 7.5), p(12, 3))
            line(p(4, 7.5), p(12, 12), p(20, 7.5))
            line(p(12, 12), p(12, 21))
        case .images:
            path.addRect(CGRect(x: 3, y: 4, width: 18, height: 6))
            path.addRect(CGRect(x: 3, y: 14, width: 18, height: 6))
        case .volumes:
            // M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3v12c0 1.7-3.6 3-8 3s-8-1.3-8-3z  M4 6c0 1.7 3.6 3 8 3s8-1.3 8-3
            path.move(to: p(4, 6))
            path.addCurve(to: p(12, 3), control1: p(4, 4.3), control2: p(7.6, 3))
            path.addCurve(to: p(20, 6), control1: p(16.4, 3), control2: p(20, 4.3))
            path.addLine(to: p(20, 18))
            path.addCurve(to: p(12, 21), control1: p(20, 19.7), control2: p(16.4, 21))
            path.addCurve(to: p(4, 18), control1: p(7.6, 21), control2: p(4, 19.7))
            path.closeSubpath()
            path.move(to: p(4, 6))
            path.addCurve(to: p(12, 9), control1: p(4, 7.7), control2: p(7.6, 9))
            path.addCurve(to: p(20, 6), control1: p(16.4, 9), control2: p(20, 7.7))
        case .networks:
            // Topology: M9 3h6v5H9z M3 16h6v5H3z M15 16h6v5h-6z M12 8v4 M6 16v-4h12v4
            path.addRect(CGRect(x: 9, y: 3, width: 6, height: 5))
            path.addRect(CGRect(x: 3, y: 16, width: 6, height: 5))
            path.addRect(CGRect(x: 15, y: 16, width: 6, height: 5))
            line(p(12, 8), p(12, 12))
            line(p(6, 16), p(6, 12), p(18, 12), p(18, 16))
        case .cleanup, .trash:
            line(p(4, 7), p(20, 7))
            line(p(9, 7), p(9, 4), p(15, 4), p(15, 7))
            line(p(6, 7), p(7, 20), p(17, 20), p(18, 7))
        case .profiles:
            path.addRect(CGRect(x: 4, y: 5, width: 16, height: 10))
            line(p(8, 19), p(16, 19))
            line(p(12, 15), p(12, 19))
        case .settings:
            path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            line(p(12, 2), p(12, 5)); line(p(12, 19), p(12, 22))
            line(p(2, 12), p(5, 12)); line(p(19, 12), p(22, 12))
            line(p(4.9, 4.9), p(7, 7)); line(p(17, 17), p(19.1, 19.1))
            line(p(4.9, 19.1), p(7, 17)); line(p(17, 7), p(19.1, 4.9))
        case .refresh:
            // M20 11a8 8 0 1 0-2.3 5.7  M20 4v7h-7
            path.addArc(center: p(12, 11), radius: 8, startAngle: .degrees(0), endAngle: .degrees(45), clockwise: true)
            line(p(20, 4), p(20, 11), p(13, 11))
        case .sort:
            line(p(4, 7), p(20, 7)); line(p(7, 12), p(17, 12)); line(p(10, 17), p(14, 17))
        case .search:
            path.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            line(p(20, 20), p(16, 16))
        case .plus:
            line(p(12, 5), p(12, 19)); line(p(5, 12), p(19, 12))
        case .chevronLeft:
            line(p(15, 5), p(8, 12), p(15, 19))
        case .chevronRight:
            line(p(9, 6), p(15, 12), p(9, 18))
        case .folder:
            line(p(3, 7), p(10, 7), p(12, 9), p(21, 9), p(21, 19), p(3, 19), p(3, 7))
        case .copy:
            path.addRoundedRect(in: CGRect(x: 8, y: 8, width: 12, height: 12), cornerSize: CGSize(width: 2, height: 2))
            line(p(16, 8), p(16, 5), p(15, 4), p(5, 4), p(4, 5), p(4, 15), p(5, 16), p(8, 16))
        case .external:
            line(p(7, 17), p(17, 7)); line(p(9, 7), p(17, 7), p(17, 15))
        case .check:
            line(p(5, 12), p(10, 17), p(19, 7))
        case .minus:
            line(p(6, 12), p(18, 12))
        case .warning:
            line(p(12, 3), p(22, 21), p(2, 21), p(12, 3))
            line(p(12, 10), p(12, 15))
            line(p(12, 18), p(12, 18.5))
        case .terminal:
            line(p(4, 17), p(10, 12), p(4, 7)); line(p(12, 19), p(20, 19))
        case .download:
            line(p(12, 4), p(12, 15)); line(p(7, 10), p(12, 15), p(17, 10)); line(p(5, 20), p(19, 20))
        }
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }
}

extension LineIcon {
    /// SVG `stroke-width` is in the 24-unit box, so it scales with the icon.
    func icon(_ color: Color, size: CGFloat, svgStrokeWidth: CGFloat = 2) -> some View {
        stroke(color, style: StrokeStyle(lineWidth: svgStrokeWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
