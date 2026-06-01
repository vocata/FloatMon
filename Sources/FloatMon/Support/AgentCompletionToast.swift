import AppKit
import SwiftUI

@MainActor
enum AgentCompletionToastController {
    static func show(_ notice: AgentCompletionNotice, near anchorRect: CGRect) {
        AgentCompletionToastPanel.shared.show(notice, near: anchorRect)
    }

    static func hide() {
        AgentCompletionToastPanel.shared.hide()
    }
}

@MainActor
private final class AgentCompletionToastPanel {
    static let shared = AgentCompletionToastPanel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AgentCompletionToastView>?

    func show(_ notice: AgentCompletionNotice, near anchorRect: CGRect) {
        let content = AgentCompletionToastView(notice: notice)
        let hostingView = hostingView ?? NSHostingView(rootView: content)
        hostingView.rootView = content
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        self.hostingView = hostingView

        let panel = panel ?? makePanel(contentView: hostingView)
        panel.contentView = hostingView
        panel.setFrame(frame(for: hostingView.fittingSize, near: anchorRect), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = contentView
        return panel
    }

    private func frame(for size: NSSize, near anchorRect: NSRect) -> NSRect {
        let padding: CGFloat = 10
        let visibleFrame = NSScreen.screens
            .first(where: { $0.frame.intersects(anchorRect) })?
            .visibleFrame
            ?? NSScreen.main?.visibleFrame

        var origin = NSPoint(
            x: anchorRect.minX - size.width - padding,
            y: anchorRect.midY - size.height / 2
        )

        if origin.x < (visibleFrame?.minX ?? 0) + padding {
            origin.x = anchorRect.maxX + padding
        }

        if let visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + padding), visibleFrame.maxX - size.width - padding)
            origin.y = min(max(origin.y, visibleFrame.minY + padding), visibleFrame.maxY - size.height - padding)
        }

        return NSRect(origin: origin, size: size)
    }
}

private struct AgentCompletionToastView: View {
    let notice: AgentCompletionNotice

    var body: some View {
        let shape = Capsule(style: .continuous)

        HStack(spacing: 9) {
            Circle()
                .fill(Color(red: 0.25, green: 0.92, blue: 0.42))
                .frame(width: 8, height: 8)
                .shadow(color: Color(red: 0.25, green: 0.92, blue: 0.42).opacity(0.45), radius: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                Text(notice.detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 210, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            shape
                .fill(.black.opacity(0.92))
        }
        .overlay {
            shape
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .clipShape(shape)
    }
}
