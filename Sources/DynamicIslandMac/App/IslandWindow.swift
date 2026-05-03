import AppKit
import QuartzCore
import SwiftUI

final class IslandWindow: NSPanel {
    private enum Metrics {
        static let collapsedSize = NSSize(width: 68, height: 68)
        static let expandedSize = NSSize(width: 520, height: 390)
        static let animationDuration: TimeInterval = 0.26
    }

    private let processStore: ProcessStore
    private var collapsedCenterBeforeExpansion: NSPoint?

    init(processStore: ProcessStore) {
        self.processStore = processStore

        super.init(
            contentRect: NSRect(origin: .zero, size: Metrics.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true

        let hostingView = ClearHostingView(rootView: IslandView(store: processStore))
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        hostingView.frame = contentRect(forFrameRect: frame)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hostingView
    }

    func show() {
        positionForPrimaryScreen(collapsed: true)
        orderFrontRegardless()
    }

    func resize(expanded: Bool) {
        let targetFrame = expanded ? expandedFrame(from: frame) : collapsedFrame(from: frame)
        animateFrame(to: targetFrame)
    }

    func markCustomPosition() {
        collapsedCenterBeforeExpansion = nil
    }

    private func positionForPrimaryScreen(collapsed: Bool) {
        guard let screen = NSScreen.screens.first else { return }

        let size = collapsed ? Metrics.collapsedSize : Metrics.expandedSize
        let trailingInset: CGFloat = 22
        let frame = screen.visibleFrame
        let x = frame.maxX - size.width - trailingInset
        let y = frame.midY - size.height / 2

        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true, animate: false)
    }

    private func expandedFrame(from currentFrame: NSRect) -> NSRect {
        collapsedCenterBeforeExpansion = NSPoint(x: currentFrame.midX, y: currentFrame.midY)
        return frame(
            size: Metrics.expandedSize,
            centeredOn: NSPoint(x: currentFrame.midX, y: currentFrame.midY),
            constrainedTo: currentFrame.screen?.visibleFrame
        )
    }

    private func collapsedFrame(from currentFrame: NSRect) -> NSRect {
        let center = collapsedCenterBeforeExpansion ?? NSPoint(x: currentFrame.midX, y: currentFrame.midY)

        return frame(
            size: Metrics.collapsedSize,
            centeredOn: center,
            constrainedTo: nil
        )
    }

    private func frame(size: NSSize, centeredOn center: NSPoint, constrainedTo visibleFrame: NSRect?) -> NSRect {
        let visibleFrame = visibleFrame ?? NSScreen.screens.first?.visibleFrame
        var origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)

        if let visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }

        return NSRect(origin: origin, size: size)
    }

    private func animateFrame(to targetFrame: NSRect) {
        let currentFrame = frame
        guard currentFrame != targetFrame else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(targetFrame, display: true)
        }
    }
}

private extension NSRect {
    var screen: NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.intersects(self)
        }
    }

}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
