import AppKit

/// The ColiUI mark: a llama inside a rounded console frame, drawn in a 100×100 space.
enum Glyph {
    static func framePath() -> CGPath {
        CGPath(roundedRect: CGRect(x: 8, y: 8, width: 84, height: 84), cornerWidth: 18, cornerHeight: 18, transform: nil)
    }

    static func llamaPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 30, y: 95))
        path.addLine(to: CGPoint(x: 32, y: 44))
        path.addCurve(to: CGPoint(x: 37, y: 30), control1: CGPoint(x: 32, y: 36), control2: CGPoint(x: 34, y: 32))
        path.addLine(to: CGPoint(x: 35, y: 16))
        path.addLine(to: CGPoint(x: 41, y: 27))
        path.addLine(to: CGPoint(x: 44, y: 14))
        path.addLine(to: CGPoint(x: 47, y: 28))
        path.addCurve(to: CGPoint(x: 66, y: 36), control1: CGPoint(x: 52, y: 29), control2: CGPoint(x: 60, y: 32))
        path.addCurve(to: CGPoint(x: 66, y: 46), control1: CGPoint(x: 69, y: 38), control2: CGPoint(x: 69, y: 44))
        path.addCurve(to: CGPoint(x: 53, y: 50), control1: CGPoint(x: 62, y: 48), control2: CGPoint(x: 57, y: 49))
        path.addCurve(to: CGPoint(x: 50, y: 70), control1: CGPoint(x: 51, y: 54), control2: CGPoint(x: 50, y: 60))
        path.addLine(to: CGPoint(x: 52, y: 95))
        path.closeSubpath()
        return path
    }

    /// Template image for the menu bar; `dimmed` renders the "VM stopped" state at 35 %.
    static func menuBarImage(dimmed: Bool, side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setAlpha(dimmed ? 0.35 : 1)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.scaleBy(x: rect.width / 100, y: rect.height / 100)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(9)
            context.addPath(framePath())
            context.strokePath()
            context.translateBy(x: 12, y: 12)
            context.scaleBy(x: 0.78, y: 0.78)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(llamaPath())
            context.fillPath()
            context.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = dimmed ? "ColiUI, Colima stopped" : "ColiUI, Colima running"
        return image
    }
}
