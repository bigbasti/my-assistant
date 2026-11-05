// Renders the app icon: a glassy blue–violet squircle with white sparkles.
// Usage: swift scripts/make-icon.swift  (writes Resources/AppIcon.icns)
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: the shape fills ~80 % of the canvas, centred.
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset * 1.1, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Soft drop shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill(); squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Base gradient (Teams violet → Outlook blue → meeting green hint).
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(red: 0.40, green: 0.33, blue: 0.85, alpha: 1),
        NSColor(red: 0.13, green: 0.45, blue: 0.93, alpha: 1),
        NSColor(red: 0.05, green: 0.66, blue: 0.62, alpha: 1),
    ])!.draw(in: rect, angle: -60)
    // Glass highlight: a bright sheen across the top half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.38), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY - rect.height * 0.05, width: rect.width, height: rect.height * 0.55), angle: -90)
    // A docked "panel" strip on the right edge, hinting at the app's layout.
    let strip = NSRect(x: rect.maxX - rect.width * 0.28, y: rect.minY + rect.height * 0.12,
                       width: rect.width * 0.17, height: rect.height * 0.76)
    NSColor.white.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: strip, xRadius: strip.width * 0.3, yRadius: strip.width * 0.3).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Inner rim for the glass edge.
    NSColor.white.withAlphaComponent(0.45).setStroke()
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.004, dy: s * 0.004), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, s * 0.006)
    rim.stroke()

    // Sparkles symbol, white, slightly left of centre (the panel sits on the right).
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.36, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = sym.size
        let origin = NSPoint(x: rect.minX + rect.width * 0.38 - size.width / 2, y: rect.midY - size.height / 2)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.white.withAlphaComponent(0.6)
        glow.shadowBlurRadius = s * 0.025
        glow.set()
        sym.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: tmp.appendingPathComponent("icon_\(name).png"))
}
try render(1024).write(to: out.deletingPathExtension().appendingPathExtension("png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out.path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
