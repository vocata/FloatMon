import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let icons: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in icons {
    let image = NSImage(size: NSSize(width: icon.1, height: icon.1))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: icon.1, height: icon.1)
    let cornerRadius = icon.1 * 0.23
    let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSColor(calibratedRed: 0.03, green: 0.035, blue: 0.045, alpha: 1).setFill()
    background.fill()

    let islandRect = rect.insetBy(dx: icon.1 * 0.16, dy: icon.1 * 0.29)
    let islandPath = NSBezierPath(
        roundedRect: islandRect,
        xRadius: islandRect.height / 2,
        yRadius: islandRect.height / 2
    )
    NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1).setFill()
    islandPath.fill()

    let glowRect = NSRect(
        x: icon.1 * 0.18,
        y: icon.1 * 0.16,
        width: icon.1 * 0.28,
        height: icon.1 * 0.28
    )
    let glowPath = NSBezierPath(ovalIn: glowRect)
    NSColor(calibratedRed: 0.22, green: 0.92, blue: 0.48, alpha: 1).setFill()
    glowPath.fill()

    let cardRect = NSRect(
        x: icon.1 * 0.34,
        y: icon.1 * 0.22,
        width: icon.1 * 0.46,
        height: icon.1 * 0.46
    )
    let cardPath = NSBezierPath(
        roundedRect: cardRect,
        xRadius: icon.1 * 0.10,
        yRadius: icon.1 * 0.10
    )
    NSColor(calibratedRed: 0.25, green: 0.40, blue: 1.0, alpha: 1).setFill()
    cardPath.fill()

    let dotPath = NSBezierPath(ovalIn: NSRect(
        x: icon.1 * 0.66,
        y: icon.1 * 0.52,
        width: icon.1 * 0.10,
        height: icon.1 * 0.10
    ))
    NSColor.white.withAlphaComponent(0.95).setFill()
    dotPath.fill()

    let linePath = NSBezierPath()
    linePath.move(to: NSPoint(x: icon.1 * 0.42, y: icon.1 * 0.42))
    linePath.line(to: NSPoint(x: icon.1 * 0.56, y: icon.1 * 0.34))
    linePath.line(to: NSPoint(x: icon.1 * 0.70, y: icon.1 * 0.43))
    linePath.lineWidth = max(2, icon.1 * 0.035)
    linePath.lineCapStyle = .round
    linePath.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.92).setStroke()
    linePath.stroke()

    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(icon.0))
}
