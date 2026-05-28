import AppKit
import SwiftUI

enum ExternalHoverTooltipTone {
    case neutral
    case green
    case cyan
    case orange
    case red
    case blue

    var color: Color {
        switch self {
        case .neutral:
            return .white.opacity(0.46)
        case .green:
            return Color(red: 0.20, green: 0.92, blue: 0.38)
        case .cyan:
            return Color(red: 0.00, green: 0.78, blue: 1.00)
        case .orange:
            return Color(red: 1.00, green: 0.58, blue: 0.08)
        case .red:
            return Color(red: 1.00, green: 0.18, blue: 0.18)
        case .blue:
            return Color(red: 0.18, green: 0.46, blue: 1.00)
        }
    }
}

struct ExternalHoverTooltipPayload {
    let title: String
    let subtitle: String?
    let detailLines: [String]
    let systemImage: String?
    let image: NSImage?
    let agentProvider: AgentProvider?
    let tone: ExternalHoverTooltipTone
}

enum ExternalHoverTooltipController {
    @MainActor
    static func hide() {
        ExternalTooltipPanel.shared.dismissActiveHover()
    }

    @MainActor
    static func dismissActiveHover() {
        ExternalTooltipPanel.shared.dismissActiveHover()
    }

    @MainActor
    static func beginPointerInteraction() {
        ExternalTooltipPanel.shared.beginPointerInteraction()
    }

    @MainActor
    static func endPointerInteraction() {
        ExternalTooltipPanel.shared.endPointerInteraction()
    }
}

struct ExternalHoverTooltipModifier: ViewModifier {
    let payload: ExternalHoverTooltipPayload

    func body(content: Content) -> some View {
        content.overlay {
            ExternalTooltipTrackingView(payload: payload)
        }
    }
}

extension View {
    func externalHoverTooltip(_ text: String) -> some View {
        externalHoverCard(title: text)
    }

    func externalHoverCard(
        title: String,
        subtitle: String? = nil,
        detailLines: [String] = [],
        systemImage: String? = nil,
        image: NSImage? = nil,
        agentProvider: AgentProvider? = nil,
        tone: ExternalHoverTooltipTone = .neutral
    ) -> some View {
        modifier(
            ExternalHoverTooltipModifier(
                payload: ExternalHoverTooltipPayload(
                    title: title,
                    subtitle: subtitle,
                    detailLines: detailLines,
                    systemImage: systemImage,
                    image: image,
                    agentProvider: agentProvider,
                    tone: tone
                )
            )
        )
    }
}

private struct ExternalTooltipTrackingView: NSViewRepresentable {
    let payload: ExternalHoverTooltipPayload

    func makeNSView(context: Context) -> TooltipTrackingNSView {
        TooltipTrackingNSView(payload: payload)
    }

    func updateNSView(_ nsView: TooltipTrackingNSView, context: Context) {
        nsView.payload = payload
    }
}

private final class TooltipTrackingNSView: NSView {
    var payload: ExternalHoverTooltipPayload {
        didSet {
            if isHovering {
                ExternalTooltipPanel.shared.show(payload: payload, near: screenRect(), hoverID: hoverID)
            }
        }
    }

    private var isHovering = false
    private var hoverID: Int?

    init(payload: ExternalHoverTooltipPayload) {
        self.payload = payload
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        let hoverID = ExternalTooltipPanel.shared.beginHover()
        self.hoverID = hoverID
        ExternalTooltipPanel.shared.show(payload: payload, near: screenRect(), hoverID: hoverID)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if let hoverID {
            ExternalTooltipPanel.shared.endHover(hoverID)
        } else {
            ExternalTooltipPanel.shared.hide()
        }
        self.hoverID = nil
    }

    override func mouseDown(with event: NSEvent) {
        ExternalTooltipPanel.shared.dismissActiveHover()
        super.mouseDown(with: event)
    }

    private func screenRect() -> NSRect {
        guard let window else { return .zero }
        let windowRect = convert(bounds, to: nil)
        return window.convertToScreen(windowRect)
    }
}

@MainActor
private final class ExternalTooltipPanel {
    static let shared = ExternalTooltipPanel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<TooltipContent>?
    private var nextHoverID = 0
    private var activeHoverID: Int?
    private var currentHoverIDs: Set<Int> = []
    private var dismissedHoverIDs: Set<Int> = []
    private var pointerInteractionActive = false

    func beginHover() -> Int {
        nextHoverID += 1
        activeHoverID = nextHoverID
        currentHoverIDs.insert(nextHoverID)
        return nextHoverID
    }

    func show(payload: ExternalHoverTooltipPayload, near anchorRect: NSRect, hoverID: Int? = nil) {
        guard !pointerInteractionActive else {
            panel?.orderOut(nil)
            return
        }

        if let hoverID, !currentHoverIDs.contains(hoverID) {
            panel?.orderOut(nil)
            return
        }

        if let hoverID, dismissedHoverIDs.contains(hoverID) {
            panel?.orderOut(nil)
            return
        }

        let content = TooltipContent(payload: payload)
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

    func dismissActiveHover() {
        if let activeHoverID {
            dismissedHoverIDs.insert(activeHoverID)
        }
        hide()
    }

    func endHover(_ hoverID: Int) {
        if activeHoverID == hoverID {
            activeHoverID = nil
        }
        currentHoverIDs.remove(hoverID)
        dismissedHoverIDs.remove(hoverID)
        hide()
    }

    func beginPointerInteraction() {
        pointerInteractionActive = true
        dismissActiveHover()
    }

    func endPointerInteraction() {
        pointerInteractionActive = false
        activeHoverID = nil
        currentHoverIDs.removeAll()
        dismissedHoverIDs.removeAll()
        hide()
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

private struct TooltipContent: View {
    let payload: ExternalHoverTooltipPayload

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                if let subtitle = payload.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                if !payload.detailLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(payload.detailLines.prefix(4).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: 190, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.26), radius: 12, y: 4)
        }
    }

    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.075))
                .frame(width: 28, height: 28)

            if let agentProvider = payload.agentProvider {
                AgentIcon(provider: agentProvider, size: 28, fontSize: 10)
            } else if let image = payload.image {
                AppIconView(image: image, size: 28)
            } else if let systemImage = payload.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Circle()
                .fill(payload.tone.color)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.86), lineWidth: 1.5)
                }
                .offset(x: 2, y: 2)
        }
    }
}
