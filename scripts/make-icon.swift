#!/usr/bin/env swift
import AppKit

let target = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: target).deletingPathExtension().appendingPathExtension("iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func icon(_ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let s = CGFloat(pixels) / 1024
    let markStroke = max(30.0, 1.0 / s) // At least one device pixel at small icon sizes.
    NSAffineTransform(transform: AffineTransform(scaleByX: s, byY: s)).concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 194, yRadius: 194)
    // Light edition of SQLLY's original cylinder artwork. Keep the same
    // geometry and native icon inset, with contrast tuned for small sizes.
    NSColor(srgbRed: 0.98, green: 0.98, blue: 0.965, alpha: 1).setFill()
    background.fill()
    NSColor(srgbRed: 0.82, green: 0.84, blue: 0.815, alpha: 1).setStroke()
    background.lineWidth = 2
    background.stroke()
    // Original artwork. The familiar cylinder metaphor was studied in the
    // Bootstrap database reference; no Bootstrap SVG/path/font is copied.
    NSColor(srgbRed: 0.125, green: 0.16, blue: 0.14, alpha: 1).setStroke()
    let sides = NSBezierPath()
    sides.move(to: NSPoint(x: 286, y: 702))
    sides.line(to: NSPoint(x: 286, y: 338))
    sides.curve(to: NSPoint(x: 738, y: 338), controlPoint1: NSPoint(x: 286, y: 228), controlPoint2: NSPoint(x: 738, y: 228))
    sides.line(to: NSPoint(x: 738, y: 702))
    sides.lineWidth = markStroke; sides.lineCapStyle = .round; sides.lineJoinStyle = .round; sides.stroke()
    let crown = NSBezierPath(ovalIn: NSRect(x: 286, y: 622, width: 452, height: 160))
    crown.lineWidth = markStroke; crown.stroke()
    for y in [575.0, 454.0] {
        let layer = NSBezierPath()
        layer.move(to: NSPoint(x: 286, y: y))
        layer.curve(to: NSPoint(x: 738, y: y), controlPoint1: NSPoint(x: 286, y: y - 110), controlPoint2: NSPoint(x: 738, y: y - 110))
        layer.lineWidth = markStroke; layer.lineCapStyle = .round; layer.stroke()
    }
    NSColor(srgbRed: 0.14, green: 0.52, blue: 0.29, alpha: 1).setStroke()
    let active = NSBezierPath()
    active.move(to: NSPoint(x: 444, y: 274))
    active.curve(to: NSPoint(x: 580, y: 274), controlPoint1: NSPoint(x: 485, y: 261), controlPoint2: NSPoint(x: 539, y: 261))
    active.lineWidth = markStroke; active.lineCapStyle = .round; active.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try icon(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", iconset.path, "-o", target]; try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
