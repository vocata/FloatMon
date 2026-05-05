import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
let tiffDirectoryURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("DynamicIslandMacAppIcon.tiffset", isDirectory: true)
let combinedTIFFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("DynamicIslandMacAppIcon.tiff")

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: tiffDirectoryURL)
try FileManager.default.createDirectory(at: tiffDirectoryURL, withIntermediateDirectories: true)

let icons: [(name: String, size: CGFloat)] = [
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

var tiffURLsBySize: [Int: URL] = [:]
for icon in icons {
    let image = iconImage(size: icon.size)

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(icon.name))

    let pixelSize = Int(icon.size)
    if tiffURLsBySize[pixelSize] == nil {
        let tiffURL = tiffDirectoryURL.appendingPathComponent("\(pixelSize).tiff")
        try tiffData.write(to: tiffURL)
        tiffURLsBySize[pixelSize] = tiffURL
    }
}

try createICNS()

private func iconImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    drawBackground(in: rect, scale: size)
    drawCircuitGrid(in: rect, scale: size)
    drawFloatingBall(in: rect, scale: size)
    drawStatusBadge(in: rect, scale: size)

    image.unlockFocus()
    return image
}

private func drawBackground(in rect: NSRect, scale: CGFloat) {
    let radius = scale * 0.23
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGradient(colors: [
        color(0.015, 0.017, 0.026),
        color(0.025, 0.034, 0.050),
        color(0.035, 0.020, 0.060)
    ])?.draw(in: path, angle: -35)

    let glow = NSBezierPath(ovalIn: rect.insetBy(dx: -scale * 0.25, dy: scale * 0.36))
    color(0.12, 0.78, 1.0, alpha: 0.16).setFill()
    glow.fill()

    color(1, 1, 1, alpha: 0.10).setStroke()
    path.lineWidth = max(1, scale * 0.008)
    path.stroke()
}

private func drawCircuitGrid(in rect: NSRect, scale: CGFloat) {
    let lineWidth = max(1, scale * 0.006)
    color(0.16, 0.95, 0.78, alpha: 0.18).setStroke()

    for index in 0..<4 {
        let offset = CGFloat(index) * scale * 0.12
        drawTrace(
            points: [
                NSPoint(x: rect.minX + scale * 0.13, y: rect.maxY - scale * (0.18 + offset)),
                NSPoint(x: rect.minX + scale * 0.24, y: rect.maxY - scale * (0.18 + offset)),
                NSPoint(x: rect.minX + scale * 0.31, y: rect.maxY - scale * (0.24 + offset))
            ],
            lineWidth: lineWidth
        )
    }

    for index in 0..<3 {
        let x = rect.maxX - scale * (0.17 + CGFloat(index) * 0.12)
        drawTrace(
            points: [
                NSPoint(x: x, y: rect.minY + scale * 0.16),
                NSPoint(x: x, y: rect.minY + scale * 0.27),
                NSPoint(x: x - scale * 0.07, y: rect.minY + scale * 0.34)
            ],
            lineWidth: lineWidth
        )
    }
}

private func drawFloatingBall(in rect: NSRect, scale: CGFloat) {
    let ball = NSRect(
        x: rect.midX - scale * 0.35,
        y: rect.midY - scale * 0.35,
        width: scale * 0.70,
        height: scale * 0.70
    )

    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, alpha: 0.58)
    shadow.shadowBlurRadius = scale * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -scale * 0.035)
    shadow.set()

    let ballPath = NSBezierPath(ovalIn: ball)
    NSGradient(colors: [
        color(0.015, 0.016, 0.020),
        color(0.030, 0.034, 0.046),
        color(0.000, 0.000, 0.000)
    ])?.draw(in: ballPath, angle: 120)

    NSShadow().set()
    color(1, 1, 1, alpha: 0.11).setStroke()
    ballPath.lineWidth = max(1, scale * 0.010)
    ballPath.stroke()

    let highlight = NSBezierPath(ovalIn: NSRect(
        x: ball.minX + scale * 0.16,
        y: ball.maxY - scale * 0.23,
        width: scale * 0.23,
        height: scale * 0.12
    ))
    color(1, 1, 1, alpha: 0.075).setFill()
    highlight.fill()

    drawFloatingBallCore(in: ball, scale: scale)
    drawResourceSignal(in: ball, scale: scale)
}

private func drawFloatingBallCore(in ball: NSRect, scale: CGFloat) {
    guard scale >= 64 else { return }

    let core = NSRect(
        x: ball.midX - scale * 0.18,
        y: ball.midY - scale * 0.16,
        width: scale * 0.36,
        height: scale * 0.32
    )
    let corePath = NSBezierPath(
        roundedRect: core,
        xRadius: scale * 0.085,
        yRadius: scale * 0.085
    )
    NSGradient(colors: [
        color(0.16, 0.20, 0.34),
        color(0.08, 0.10, 0.16)
    ])?.draw(in: corePath, angle: 90)

    color(1, 1, 1, alpha: 0.16).setStroke()
    corePath.lineWidth = max(1, scale * 0.006)
    corePath.stroke()

    let promptFont = NSFont.monospacedSystemFont(ofSize: max(8, scale * 0.105), weight: .bold)
    let promptAttributes: [NSAttributedString.Key: Any] = [
        .font: promptFont,
        .foregroundColor: color(0.25, 1.0, 0.55)
    ]
    NSString(string: "$").draw(
        in: NSRect(
            x: core.minX + scale * 0.060,
            y: core.maxY - scale * 0.165,
            width: scale * 0.11,
            height: scale * 0.13
        ),
        withAttributes: promptAttributes
    )

    let cursorPath = NSBezierPath(roundedRect: NSRect(
        x: core.minX + scale * 0.17,
        y: core.maxY - scale * 0.126,
        width: scale * 0.11,
        height: max(2, scale * 0.018)
    ), xRadius: scale * 0.009, yRadius: scale * 0.009)
    color(0.44, 0.87, 1.0, alpha: 0.92).setFill()
    cursorPath.fill()
}

private func drawResourceSignal(in rect: NSRect, scale: CGFloat) {
    let lineWidth = max(2, scale * 0.018)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + scale * 0.19, y: rect.minY + scale * 0.23))
    path.line(to: NSPoint(x: rect.minX + scale * 0.29, y: rect.minY + scale * 0.20))
    path.line(to: NSPoint(x: rect.minX + scale * 0.38, y: rect.minY + scale * 0.32))
    path.line(to: NSPoint(x: rect.minX + scale * 0.50, y: rect.minY + scale * 0.18))

    color(0.20, 1.0, 0.66, alpha: 0.92).setStroke()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()

    let glow = path.copy() as! NSBezierPath
    color(0.20, 1.0, 0.66, alpha: 0.22).setStroke()
    glow.lineWidth = lineWidth * 2.6
    glow.stroke()
}

private func drawStatusBadge(in rect: NSRect, scale: CGFloat) {
    let badge = NSRect(
        x: rect.maxX - scale * 0.31,
        y: rect.minY + scale * 0.18,
        width: scale * 0.19,
        height: scale * 0.19
    )
    let outer = NSBezierPath(ovalIn: badge)
    color(0.01, 0.012, 0.018).setFill()
    outer.fill()

    let inner = NSBezierPath(ovalIn: badge.insetBy(dx: scale * 0.035, dy: scale * 0.035))
    NSGradient(colors: [
        color(1.0, 0.20, 0.22),
        color(1.0, 0.62, 0.18)
    ])?.draw(in: inner, angle: 45)
}

private func drawTrace(points: [NSPoint], lineWidth: CGFloat) {
    guard let first = points.first else { return }

    let path = NSBezierPath()
    path.move(to: first)
    points.dropFirst().forEach { path.line(to: $0) }
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()

    points.forEach { point in
        NSBezierPath(ovalIn: NSRect(
            x: point.x - lineWidth * 1.3,
            y: point.y - lineWidth * 1.3,
            width: lineWidth * 2.6,
            height: lineWidth * 2.6
        )).fill()
    }
}

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private func createICNS() throws {
    let tiffURLs = [16, 32, 128, 256, 512, 1024].compactMap { tiffURLsBySize[$0] }
    try run(
        executable: "/usr/bin/tiffutil",
        arguments: ["-catnosizecheck"] + tiffURLs.map(\.path) + ["-out", combinedTIFFURL.path]
    )
    try run(executable: "/usr/bin/tiff2icns", arguments: [combinedTIFFURL.path, icnsURL.path])
}

private func run(executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
}
