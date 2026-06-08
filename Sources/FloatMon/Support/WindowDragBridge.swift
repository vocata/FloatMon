import AppKit
import SwiftUI

enum WindowSwipeDirection {
    case left
    case right

    static func accumulatedScrollDirection(_ value: CGFloat) -> WindowSwipeDirection {
        value < 0 ? .left : .right
    }
}

enum WindowVerticalSwipeDirection {
    case up
    case down

    static func accumulatedScrollDirection(_ value: CGFloat) -> WindowVerticalSwipeDirection {
        value < 0 ? .up : .down
    }
}

struct WindowDragBridge: NSViewRepresentable {
    let onClick: () -> Void
    var onPressChanged: (Bool) -> Void = { _ in }
    var onRightClick: (() -> Void)?
    var onHorizontalSwipe: ((WindowSwipeDirection) -> Void)?
    var onVerticalSwipe: ((WindowVerticalSwipeDirection) -> Void)?

    func makeNSView(context: Context) -> DragView {
        DragView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onPressChanged = onPressChanged
        context.coordinator.onRightClick = onRightClick
        context.coordinator.onHorizontalSwipe = onHorizontalSwipe
        context.coordinator.onVerticalSwipe = onVerticalSwipe
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onClick: onClick,
            onPressChanged: onPressChanged,
            onRightClick: onRightClick,
            onHorizontalSwipe: onHorizontalSwipe,
            onVerticalSwipe: onVerticalSwipe
        )
    }

    final class Coordinator {
        var onClick: () -> Void
        var onPressChanged: (Bool) -> Void
        var onRightClick: (() -> Void)?
        var onHorizontalSwipe: ((WindowSwipeDirection) -> Void)?
        var onVerticalSwipe: ((WindowVerticalSwipeDirection) -> Void)?

        init(
            onClick: @escaping () -> Void,
            onPressChanged: @escaping (Bool) -> Void,
            onRightClick: (() -> Void)?,
            onHorizontalSwipe: ((WindowSwipeDirection) -> Void)?,
            onVerticalSwipe: ((WindowVerticalSwipeDirection) -> Void)?
        ) {
            self.onClick = onClick
            self.onPressChanged = onPressChanged
            self.onRightClick = onRightClick
            self.onHorizontalSwipe = onHorizontalSwipe
            self.onVerticalSwipe = onVerticalSwipe
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
    private var accumulatedVerticalScroll: CGFloat = 0
    private var lastSwipeTimestamp: TimeInterval = 0
    private var didTriggerHorizontalSwipe = false
    private var didTriggerVerticalSwipe = false

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
            coordinator.onClick()
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
        guard coordinator.onHorizontalSwipe != nil || coordinator.onVerticalSwipe != nil else {
            super.scrollWheel(with: event)
            return
        }

        let phase = event.phase
        if phase.contains(.began) || phase.contains(.mayBegin) {
            resetSwipeTracking()
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            resetSwipeTracking()
            return
        }

        let momentumPhase = event.momentumPhase
        if !momentumPhase.isEmpty {
            if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
                resetSwipeTracking()
            }
            return
        }

        let hasGesturePhase = !phase.isEmpty
        guard !hasGesturePhase || (!didTriggerHorizontalSwipe && !didTriggerVerticalSwipe) else { return }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        if abs(deltaX) > abs(deltaY) * Metrics.horizontalDominanceRatio,
           let onHorizontalSwipe = coordinator.onHorizontalSwipe {
            handleHorizontalSwipe(deltaX: deltaX, timestamp: event.timestamp, hasGesturePhase: hasGesturePhase, onHorizontalSwipe: onHorizontalSwipe)
            return
        }

        if abs(deltaY) > abs(deltaX) * Metrics.horizontalDominanceRatio,
           let onVerticalSwipe = coordinator.onVerticalSwipe {
            handleVerticalSwipe(deltaY: deltaY, timestamp: event.timestamp, hasGesturePhase: hasGesturePhase, onVerticalSwipe: onVerticalSwipe)
            return
        }

        resetSwipeTracking()
        super.scrollWheel(with: event)
    }

    private func handleHorizontalSwipe(
        deltaX: CGFloat,
        timestamp: TimeInterval,
        hasGesturePhase: Bool,
        onHorizontalSwipe: (WindowSwipeDirection) -> Void
    ) {
        accumulatedHorizontalScroll += deltaX
        guard abs(accumulatedHorizontalScroll) >= Metrics.swipeThreshold else { return }

        guard hasGesturePhase || timestamp - lastSwipeTimestamp >= Metrics.phaseLessSwipeCooldown else {
            accumulatedHorizontalScroll = 0
            return
        }

        let direction = WindowSwipeDirection.accumulatedScrollDirection(accumulatedHorizontalScroll)
        accumulatedHorizontalScroll = 0
        accumulatedVerticalScroll = 0
        lastSwipeTimestamp = timestamp
        didTriggerHorizontalSwipe = hasGesturePhase

        onHorizontalSwipe(direction)
    }

    private func handleVerticalSwipe(
        deltaY: CGFloat,
        timestamp: TimeInterval,
        hasGesturePhase: Bool,
        onVerticalSwipe: (WindowVerticalSwipeDirection) -> Void
    ) {
        accumulatedVerticalScroll += deltaY
        guard abs(accumulatedVerticalScroll) >= Metrics.swipeThreshold else { return }

        guard hasGesturePhase || timestamp - lastSwipeTimestamp >= Metrics.phaseLessSwipeCooldown else {
            accumulatedVerticalScroll = 0
            return
        }

        let direction = WindowVerticalSwipeDirection.accumulatedScrollDirection(accumulatedVerticalScroll)
        accumulatedHorizontalScroll = 0
        accumulatedVerticalScroll = 0
        lastSwipeTimestamp = timestamp
        didTriggerVerticalSwipe = hasGesturePhase

        onVerticalSwipe(direction)
    }

    private func resetSwipeTracking() {
        accumulatedHorizontalScroll = 0
        accumulatedVerticalScroll = 0
        didTriggerHorizontalSwipe = false
        didTriggerVerticalSwipe = false
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
