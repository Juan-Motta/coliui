// Renders the DMG window background (DmgInstaller.dc.html) into Resources/dmg-background.tiff.
// Usage: swift scripts/make-dmg-background.swift
//
// The window is 660 x 400 pt. Finder draws the two icons and their labels itself; this image only holds
// the gradient, the arrow between the icons (centres at x 180 and 480, y 184) and the help line.
// The TIFF carries a 1x and a 2x image so the background stays sharp on Retina screens.
import AppKit
import Foundation

let size = CGSize(width: 660, height: 400)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/dmg-background.tiff")
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("coliui-dmg-background")

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(scale: CGFloat, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }
    bitmap.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    // Top-left origin, like the design.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)

    NSGradient(starting: color(0xFBFBFD), ending: color(0xEEF0F4))!
        .draw(in: CGRect(origin: .zero, size: size), angle: 90)

    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 282, y: 184))
    arrow.addLine(to: CGPoint(x: 374, y: 184))
    arrow.move(to: CGPoint(x: 360, y: 170))
    arrow.addLine(to: CGPoint(x: 376, y: 184))
    arrow.addLine(to: CGPoint(x: 360, y: 198))
    context.addPath(arrow)
    context.setStrokeColor(color(0xAEAEB2).cgColor)
    context.setLineWidth(4)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let help = NSAttributedString(string: "Drag ColiUI to Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: color(0x48484A),
    ])
    let width = help.size().width
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    help.draw(at: CGPoint(x: (size.width - width) / 2, y: 318))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
let normal = scratch.appendingPathComponent("background.png")
let retina = scratch.appendingPathComponent("background@2x.png")
try render(scale: 1, to: normal)
try render(scale: 2, to: retina)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", normal.path, retina.path, "-out", output.path]
try tiffutil.run()
tiffutil.waitUntilExit()
try? FileManager.default.removeItem(at: scratch)
guard tiffutil.terminationStatus == 0 else { exit(tiffutil.terminationStatus) }
print("Wrote \(output.path)")
