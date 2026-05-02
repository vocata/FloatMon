import AppKit
import SwiftUI

final class IslandWindow: NSPanel {
    private let processStore: ProcessStore

    init(processStore: ProcessStore) {
        self.processStore = processStore

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 54),
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

        let hostingView = NSHostingView(rootView: IslandView(store: processStore))
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        hostingView.frame = contentRect(forFrameRect: frame)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        contentView = hostingView
    }

    func show() {
        positionForPrimaryScreen(collapsed: true)
        orderFrontRegardless()
    }

    func resize(expanded: Bool) {
        positionForPrimaryScreen(collapsed: !expanded)
    }

    private func positionForPrimaryScreen(collapsed: Bool) {
        guard let screen = NSScreen.screens.first else { return }

        let width: CGFloat = collapsed ? 320 : 520
        let height: CGFloat = collapsed ? 54 : 390
        let topInset: CGFloat = 8
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = max(0, frame.maxY - visibleFrame.maxY)
        let cameraY = frame.maxY - menuBarHeight - height - topInset
        let cameraX = frame.midX - width / 2

        setFrame(NSRect(x: cameraX, y: cameraY, width: width, height: height), display: true, animate: false)
    }
}
