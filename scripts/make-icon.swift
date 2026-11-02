// Renders the Paper app icon (Icons.dc.html: white squircle, dark mark) into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
//
// Geometry follows the macOS icon grid: an 824 px body centred on a 1024 px canvas.
// The mark uses the design's 100-unit box: frame rect (20, 20, 60, 60) r 12.9, llama path from
// Sources/ColiUI/Shared/Glyph.swift translated by 22.9 and scaled by 0.557. Keep them in sync.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func llamaPath() -> CGPath {
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

/// Thicker frame at small sizes so it survives 16 px (design: 5.7 / 6.5 @64 / 8 @32 / 10 @16).
func frameStroke(forPixels pixels: Int) -> CGFloat {
    switch pixels {
    case ...16: 10
    case ...32: 8
    case ...64: 6.5
    default: 5.7
    }
}

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Work top-down like the SVG.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    let inset = size * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = body.width * 0.225
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Grid drop shadow (y 10 / blur 20 at 1024 px).
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 10 / 1024), blur: size * 20 / 1024,
                      color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(squircle)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Hairline edge so the white body still reads on light Docks and wallpapers.
    let edgeWidth = max(size * 2 / 1024, 0.5)
    context.addPath(CGPath(roundedRect: body.insetBy(dx: edgeWidth / 2, dy: edgeWidth / 2),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setStrokeColor(CGColor(srgbRed: 0xD1 / 255, green: 0xD1 / 255, blue: 0xD6 / 255, alpha: 1))
    context.setLineWidth(edgeWidth)
    context.strokePath()

    // Mark, in the design's 100-unit box mapped onto the body.
    let ink = CGColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    context.translateBy(x: body.minX, y: body.minY)
    context.scaleBy(x: body.width / 100, y: body.height / 100)
    context.setStrokeColor(ink)
    context.setLineWidth(frameStroke(forPixels: pixels))
    context.addPath(CGPath(roundedRect: CGRect(x: 20, y: 20, width: 60, height: 60), cornerWidth: 12.9, cornerHeight: 12.9, transform: nil))
    context.strokePath()
    context.translateBy(x: 22.9, y: 22.9)
    context.scaleBy(x: 0.557, y: 0.557)
    context.setFillColor(ink)
    context.addPath(llamaPath())
    context.fillPath()

    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
print("Previews: \(iconset.path)")
