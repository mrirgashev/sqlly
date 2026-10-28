import AppKit
import DSStore

/// Writes Finder's layout directly. This tool never drives Finder, changes
/// Finder preferences, or installs the app. Run it on a mounted writable image.
@MainActor struct SQLLYDMGLayout {
    static let size = NSSize(width: 660, height: 420)
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, ["prepare", "verify"].contains(arguments[1]) else {
            throw failure("Usage: SQLLYDMGLayout prepare|verify /Volumes/<mounted-image>")
        }
        let volume = URL(fileURLWithPath: arguments[2], isDirectory: true).standardizedFileURL
        guard volume.path.hasPrefix("/Volumes/"),
              FileManager.default.fileExists(atPath: volume.appendingPathComponent("SQLLY.app/Contents/Info.plist").path),
              try FileManager.default.destinationOfSymbolicLink(atPath: volume.appendingPathComponent("Applications").path) == "/Applications" else {
            throw failure("Expected a mounted SQLLY volume with its real application and Applications shortcut.")
        }
        if arguments[1] == "prepare" { try prepare(volume) }
        try verify(volume)
        print("Finder layout verified: 660×420, two 112-point icons, internal background alias, Applications → /Applications.")
    }

    static func prepare(_ volume: URL) throws {
        let folder = volume.appendingPathComponent(".background", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let background = folder.appendingPathComponent("installer.tiff")
        try artwork().write(to: background, options: .atomic)

        var store = DSStore()
        try store.setWindowBounds(top: 160, left: 160, bottom: 580, right: 820)
        store.setViewStyle(.iconView)
        store.setWindowSettings(.init(
            windowBounds: "{{160, 160}, {660, 420}}",
            sidebarWidth: 0, containerShowSidebar: false, showSidebar: false,
            showTabView: false, showToolbar: false, showStatusBar: false,
            showPathBar: false, viewStyle: "icnv"
        ))
        store.setIconViewSettings(.init(
            showIconPreview: true, showItemInfo: false, labelOnBottom: true,
            scrollPositionX: 0, scrollPositionY: 0, gridOffsetX: 0, gridOffsetY: 0,
            textSize: 13, iconSize: 112, gridSpacing: 80, viewOptionsVersion: 1,
            arrangeBy: "none"
        ))
        try store.setIconPosition(for: "SQLLY.app", x: 168, y: 214)
        try store.setIconPosition(for: "Applications", x: 492, y: 214)
        // Carbon aliases must be generated against this actual mounted volume;
        // a bookmark or an alias to the build folder breaks after distribution.
        try store.setBackgroundPicture(imageURL: background, relativeTo: volume)
        try store.write(to: volume.appendingPathComponent(".DS_Store"))
    }

    static func verify(_ volume: URL) throws {
        let store = try DSStore.read(from: volume.appendingPathComponent(".DS_Store"))
        guard let app = store.iconPosition(for: "SQLLY.app"), app.x == 168, app.y == 214,
              let applications = store.iconPosition(for: "Applications"), applications.x == 492, applications.y == 214,
              let options = store.iconViewSettings(), options.iconSize == 112,
              options.arrangeBy == "none", options.backgroundType == 2,
              let alias = options.backgroundImageAlias, !alias.isEmpty,
              let window = store.windowSettings(), window.showToolbar == false,
              window.showSidebar == false, window.showStatusBar == false,
              window.showPathBar == false,
              FileManager.default.fileExists(atPath: volume.appendingPathComponent(".background/installer.tiff").path)
        else { throw failure("Finder metadata is missing or has unexpected icon positions, background, or window options.") }
        // Keep personalized build paths out of the distributed Finder metadata.
        let metadata = try Data(contentsOf: volume.appendingPathComponent(".DS_Store"))
        for path in ["/Users/", "/private/var/", "/var/folders/"] {
            guard metadata.range(of: Data(path.utf8)) == nil,
                  metadata.range(of: Data(path.utf16BigEndianBytes)) == nil else {
                throw failure("Finder metadata contains a temporary or personal path.")
            }
        }
    }

    static func artwork() throws -> Data {
        let image = NSImage(size: size)
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                pixelsHigh: Int(size.height) * scale, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Cannot render installer artwork.") }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            context.shouldAntialias = true
            NSColor(srgbRed: 0.97, green: 0.978, blue: 0.97, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            let ink = NSColor(srgbRed: 0.10, green: 0.14, blue: 0.12, alpha: 1)
            let secondary = NSColor(srgbRed: 0.36, green: 0.40, blue: 0.38, alpha: 1)
            text("SQLLY", at: 343, font: .systemFont(ofSize: 27, weight: .semibold), color: ink, tracking: 2)
            text("Drag SQLLY to Applications", at: 307, font: .systemFont(ofSize: 16, weight: .medium), color: ink)
            text("Перетащите SQLLY в папку «Программы»", at: 283, font: .systemFont(ofSize: 13), color: secondary)
            NSColor(srgbRed: 0.10, green: 0.47, blue: 0.27, alpha: 1).setStroke()
            let arrow = NSBezierPath(); arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 298, y: 206)); arrow.line(to: NSPoint(x: 362, y: 206))
            arrow.move(to: NSPoint(x: 351, y: 217)); arrow.line(to: NSPoint(x: 362, y: 206)); arrow.line(to: NSPoint(x: 351, y: 195)); arrow.stroke()
            text("Then open SQLLY from Applications.", at: 78, font: .systemFont(ofSize: 13), color: secondary)
            text("После копирования откройте SQLLY из папки «Программы».", at: 56, font: .systemFont(ofSize: 11.5), color: secondary)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        guard let data = image.tiffRepresentation else { throw failure("Cannot encode installer artwork.") }
        return data
    }

    static func text(_ value: String, at y: CGFloat, font: NSFont, color: NSColor, tracking: Double = 0) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (value as NSString).draw(in: NSRect(x: 25, y: y, width: size.width - 50, height: 36), withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style, .kern: tracking
        ])
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "SQLLYDMGLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private extension String {
    var utf16BigEndianBytes: [UInt8] { utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] } }
}
