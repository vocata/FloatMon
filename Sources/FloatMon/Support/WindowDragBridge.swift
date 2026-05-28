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

struct WindowDragBridge: NSViewRepresentable {
    let onClick: () -> Void
    var onPressChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> DragView {
        DragView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onPressChanged = onPressChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onClick: onClick,
            onPressChanged: onPressChanged
        )
    }

    final class Coordinator {
        var onClick: () -> Void
        var onPressChanged: (Bool) -> Void

        init(
            onClick: @escaping () -> Void,
            onPressChanged: @escaping (Bool) -> Void
        ) {
            self.onClick = onClick
            self.onPressChanged = onPressChanged
        }
    }
}

final class DragView: NSView {
    private let coordinator: WindowDragBridge.Coordinator
    private let dragThreshold: CGFloat = 4
    private var startMouse: NSPoint?
    private var startOrigin: NSPoint?
    private var didDrag = false
    private var pressToken = 0

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
