import AppKit
import SwiftUI

enum WindowClickResolution: Equatable {
    case performClickImmediately
}

enum WindowClickPolicy {
    static func resolution(clickCount: Int) -> WindowClickResolution {
        .performClickImmediately
    }
}

enum WindowSwipeDirection {
    case left
    case right
}

struct WindowDragBridge: NSViewRepresentable {
    let onClick: () -> Void
    var onPressChanged: (Bool) -> Void = { _ in }
    var onRightClick: (() -> Void)?
    var onHorizontalSwipe: ((WindowSwipeDirection) -> Void)?

    func makeNSView(context: Context) -> DragView {
        DragView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onPressChanged = onPressChanged
        context.coordinator.onRightClick = onRightClick
        context.coordinator.onHorizontalSwipe = onHorizontalSwipe
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onClick: onClick,
            onPressChanged: onPressChanged,
            onRightClick: onRightClick,
            onHorizontalSwipe: onHorizontalSwipe
        )
    }

    final class Coordinator {
        var onClick: () -> Void
        var onPressChanged: (Bool) -> Void
        var onRightClick: (() -> Void)?
        var onHorizontalSwipe: ((WindowSwipeDirection) -> Void)?

        init(
            onClick: @escaping () -> Void,
            onPressChanged: @escaping (Bool) -> Void,
            onRightClick: (() -> Void)?,
            onHorizontalSwipe: ((WindowSwipeDirection) -> Void)?
        ) {
            self.onClick = onClick
            self.onPressChanged = onPressChanged
            self.onRightClick = onRightClick
            self.onHorizontalSwipe = onHorizontalSwipe
        }
    }
}

final class DragView: NSView {
    private enum Metrics {
        static let swipeThreshold: CGFloat = 18
        static let horizontalDominanceRatio: CGFloat = 1.25
        static let phaseLessSwipeCooldown: TimeInterval = 0.35
    }

    private let coordinator: WindowDragBridge.Coordinator
    private let dragThreshold: CGFloat = 4
    private var startMouse: NSPoint?
    private var startOrigin: NSPoint?
    private var didDrag = false
    private var pressToken = 0
    private var accumulatedHorizontalScroll: CGFloat = 0
    private var lastSwipeTimestamp: TimeInterval = 0
    private var didTriggerHorizontalSwipe = false

    init(coordinator: WindowDragBridge.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window as? IslandWindow else {
            super.mouseDown(with: event)
            return
        }

        Task { @MainActor in
            ExternalHoverTooltipController.beginPointerInteraction()
        }

        startMouse = NSEvent.mouseLocation
        startOrigin = window.frame.origin
        didDrag = false
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window = window as? IslandWindow,
            let startMouse,
            let startOrigin
        else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouse = NSEvent.mouseLocation
        let delta = NSPoint(
            x: currentMouse.x - startMouse.x,
            y: currentMouse.y - startMouse.y
        )
        let distance = hypot(delta.x, delta.y)

        guard didDrag || distance >= dragThreshold else { return }

        if !didDrag {
            didDrag = true
            Task { @MainActor in
                ExternalHoverTooltipController.beginPointerInteraction()
            }
            setPressed(false)
        }

        window.markCustomPosition()
        window.setFrameOrigin(
            NSPoint(
                x: startOrigin.x + delta.x,
                y: startOrigin.y + delta.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard startMouse != nil else {
            super.mouseUp(with: event)
            return
        }

        let shouldClick = !didDrag
        clearTracking()

        if shouldClick {
            switch WindowClickPolicy.resolution(clickCount: event.clickCount) {
            case .performClickImmediately:
                coordinator.onClick()
            }
            releasePressAfterClick()
        } else {
            setPressed(false)
        }

        Task { @MainActor in
            ExternalHoverTooltipController.endPointerInteraction()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let onRightClick = coordinator.onRightClick else {
            super.rightMouseDown(with: event)
            return
        }

        Task { @MainActor in
            ExternalHoverTooltipController.dismissActiveHover()
        }
        onRightClick()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let onHorizontalSwipe = coordinator.onHorizontalSwipe else {
            super.scrollWheel(with: event)
            return
        }

        let phase = event.phase
        if phase.contains(.began) || phase.contains(.mayBegin) {
            resetHorizontalSwipeTracking()
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            resetHorizontalSwipeTracking()
            return
        }

        let momentumPhase = event.momentumPhase
        if !momentumPhase.isEmpty {
            if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
                resetHorizontalSwipeTracking()
            }
            return
        }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaX) > abs(deltaY) * Metrics.horizontalDominanceRatio else {
            resetHorizontalSwipeTracking()
            super.scrollWheel(with: event)
            return
        }

        let hasGesturePhase = !phase.isEmpty
        guard !hasGesturePhase || !didTriggerHorizontalSwipe else { return }

        accumulatedHorizontalScroll += deltaX
        guard abs(accumulatedHorizontalScroll) >= Metrics.swipeThreshold else { return }

        let timestamp = event.timestamp
        guard hasGesturePhase || timestamp - lastSwipeTimestamp >= Metrics.phaseLessSwipeCooldown else {
            accumulatedHorizontalScroll = 0
            return
        }

        let direction: WindowSwipeDirection = accumulatedHorizontalScroll < 0 ? .left : .right
        accumulatedHorizontalScroll = 0
        lastSwipeTimestamp = timestamp
        didTriggerHorizontalSwipe = hasGesturePhase

        Task { @MainActor in
            ExternalHoverTooltipController.dismissActiveHover()
        }
        onHorizontalSwipe(direction)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            clearTracking()
            setPressed(false)
            Task { @MainActor in
                ExternalHoverTooltipController.endPointerInteraction()
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func clearTracking() {
        startMouse = nil
        startOrigin = nil
        didDrag = false
    }

    private func resetHorizontalSwipeTracking() {
        accumulatedHorizontalScroll = 0
        didTriggerHorizontalSwipe = false
    }

    private func setPressed(_ pressed: Bool) {
        pressToken += 1
        coordinator.onPressChanged(pressed)
    }

    private func releasePressAfterClick() {
        let token = pressToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, pressToken == token else { return }
            setPressed(false)
        }
    }

}
