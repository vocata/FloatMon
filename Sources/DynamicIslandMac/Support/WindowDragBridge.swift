import AppKit
import SwiftUI

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
        Coordinator(onClick: onClick, onPressChanged: onPressChanged)
    }

    final class Coordinator {
        var onClick: () -> Void
        var onPressChanged: (Bool) -> Void

        init(onClick: @escaping () -> Void, onPressChanged: @escaping (Bool) -> Void) {
            self.onClick = onClick
            self.onPressChanged = onPressChanged
        }
    }
}

final class DragView: NSView {
    private let coordinator: WindowDragBridge.Coordinator
    private let dragThreshold: CGFloat = 4

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

        coordinator.onPressChanged(true)

        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var didDrag = false

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            let currentMouse = NSEvent.mouseLocation
            let delta = NSPoint(
                x: currentMouse.x - startMouse.x,
                y: currentMouse.y - startMouse.y
            )
            let distance = hypot(delta.x, delta.y)

            if nextEvent.type == .leftMouseDragged || distance >= dragThreshold {
                if !didDrag {
                    coordinator.onPressChanged(false)
                }
                didDrag = true
                window.markCustomPosition()
                window.setFrameOrigin(
                    NSPoint(
                        x: startOrigin.x + delta.x,
                        y: startOrigin.y + delta.y
                    )
                )
            }

            if nextEvent.type == .leftMouseUp {
                break
            }
        }

        if !didDrag {
            coordinator.onClick()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak coordinator] in
                coordinator?.onPressChanged(false)
            }
        } else {
            coordinator.onPressChanged(false)
        }
    }
}
