import AppKit
import SwiftUI

struct AgentMonitorView: View {
    private enum Metrics {
        static let recentEventLimit = 20
        static let recentEventsHeight: CGFloat = 150
        static let detailPopoverWidth: CGFloat = 380
        static let detailPopoverHeight: CGFloat = 150
        static let detailPopoverTrailingPadding: CGFloat = 18
        static let detailPopoverBottomPadding: CGFloat = 10
        static let detailPopoverBoundaryMargin: CGFloat = 8
    }

    let snapshot: AgentSnapshot
    let refresh: () -> Void
    let registerHook: () -> Void

    @State private var isConfirmingHookRegistration = false
    @State private var selectedEvent: AgentEvent?
    @State private var detailPopoverOffset = CGSize.zero
    @State private var detailPopoverDragStart = CGSize.zero

    private var recentEvents: [AgentEvent] {
        Array(snapshot.recentEvents.filter(\.isRich).prefix(Metrics.recentEventLimit))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    header

                    if snapshot.hookStatus == .registered {
                        registeredContent
                    } else {
                        registrationContent
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)

                if selectedEvent != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeDetails()
                        }
                        .zIndex(40)
                }

                if let selectedEvent {
                    EventDetailPopover(
                        event: selectedEvent,
                        onDragChanged: { value in
                            updateDetailPopoverDrag(value, in: geometry.size)
                        },
                        onDragEnded: {
                            detailPopoverDragStart = detailPopoverOffset
                        }
                    )
                        .frame(width: Metrics.detailPopoverWidth, height: Metrics.detailPopoverHeight)
                        .padding(.trailing, Metrics.detailPopoverTrailingPadding)
                        .padding(.bottom, Metrics.detailPopoverBottomPadding)
                        .offset(detailPopoverOffset)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {}
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                        .zIndex(50)
                }
            }
            .animation(.easeOut(duration: 0.14), value: selectedEvent?.id)
            .onChange(of: snapshot.hookStatus) { _, status in
                if status == .registered {
                    isConfirmingHookRegistration = false
                }
            }
            .onChange(of: recentEvents.map(\.id)) { _, eventIDs in
                guard let selectedEvent, !eventIDs.contains(selectedEvent.id) else { return }
                closeDetails()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentIcon(size: 24, symbolSize: 13)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.provider.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(snapshot.hookStatus.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.08))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverTooltip("Refresh")
        }
    }

    private var registeredContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                InfoRow(
                    title: "Thread",
                    value: snapshot.currentThread?.title ?? "No active thread",
                    systemImage: "text.bubble"
                )
                InfoRow(
                    title: "Workspace",
                    value: workspaceLabel,
                    systemImage: "folder"
                )
                InfoRow(
                    title: "Tokens",
                    value: tokensLabel,
                    systemImage: "number"
                )
                InfoRow(
                    title: "Goal",
                    value: goalLabel,
                    systemImage: "target"
                )
            }

            eventsSection
        }
    }

    private var registrationContent: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)

            AgentIcon(size: 40, symbolSize: 20)

            VStack(spacing: 4) {
                Text(registrationTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                Text(registrationMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 360)
            }

            if isConfirmingHookRegistration {
                hookConfirmationPanel
            } else {
                Button {
                    isConfirmingHookRegistration = true
                } label: {
                    Label("Register Hook", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.12))
                        }
                }
                .buttonStyle(.plain)
                .disabled(snapshot.hookStatus == .unknown)
                .opacity(snapshot.hookStatus == .unknown ? 0.45 : 1)
            }

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hookConfirmationPanel: some View {
        VStack(spacing: 8) {
            Text("FloatMon will update ~/.codex/hooks.json and create a backup first.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 330)

            HStack(spacing: 8) {
                Button("Cancel") {
                    isConfirmingHookRegistration = false
                }
                .buttonStyle(HookConfirmationButtonStyle(isPrimary: false))

                Button("Register") {
                    registerHook()
                }
                .buttonStyle(HookConfirmationButtonStyle(isPrimary: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.065))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                }
        }
    }

    private var registrationTitle: String {
        switch snapshot.hookStatus {
        case .unknown:
            return "Checking Codex Hook"
        case .failed:
            return "Hook Registration Failed"
        case .declined:
            return "Codex Hook Skipped"
        case .missing:
            return "Codex Hook Required"
        case .registered:
            return "Codex Hook Active"
        }
    }

    private var registrationMessage: String {
        switch snapshot.hookStatus {
        case .unknown:
            return "Checking whether live Codex monitoring is available."
        case .failed(let message):
            return message
        case .declined, .missing:
            return "Register the hook to show live agent activity, tool calls, messages, tokens, and task context."
        case .registered:
            return "Live Codex monitoring is active."
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recent Events")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)

            if recentEvents.isEmpty {
                Text("No rich hook events yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.055))
                    }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(recentEvents) { event in
                            EventRow(
                                event: event,
                                isSelected: selectedEvent?.id == event.id,
                                toggleDetails: { toggleDetails(for: event) }
                            )
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.30, dampingFraction: 0.86), value: recentEvents.map(\.id))
                }
                .frame(height: Metrics.recentEventsHeight)
            }
        }
    }

    private var workspaceLabel: String {
        guard let cwd = snapshot.currentThread?.cwd, !cwd.isEmpty else {
            return snapshot.unavailableReason ?? "Unavailable"
        }

        return URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    private var tokensLabel: String {
        guard let thread = snapshot.currentThread else { return "0" }
        if let budget = snapshot.currentGoal?.tokenBudget {
            return "\(AppFormatters.integer(thread.tokensUsed)) / \(AppFormatters.integer(budget))"
        }
        return AppFormatters.integer(thread.tokensUsed)
    }

    private var goalLabel: String {
        guard let goal = snapshot.currentGoal else { return "No active goal" }
        return "\(goal.status): \(goal.objective)"
    }

    private func toggleDetails(for event: AgentEvent) {
        if selectedEvent?.id == event.id {
            closeDetails()
        } else {
            resetDetailPopoverPosition()
            selectedEvent = event
        }
    }

    private func closeDetails() {
        selectedEvent = nil
        resetDetailPopoverPosition()
    }

    private func resetDetailPopoverPosition() {
        detailPopoverOffset = .zero
        detailPopoverDragStart = .zero
    }

    private func updateDetailPopoverDrag(_ value: DragGesture.Value, in size: CGSize) {
        let proposed = CGSize(
            width: detailPopoverDragStart.width + value.translation.width,
            height: detailPopoverDragStart.height + value.translation.height
        )
        detailPopoverOffset = clampedDetailPopoverOffset(proposed, in: size)
    }

    private func clampedDetailPopoverOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        let baseX = size.width - Metrics.detailPopoverWidth - Metrics.detailPopoverTrailingPadding
        let baseY = size.height - Metrics.detailPopoverHeight - Metrics.detailPopoverBottomPadding
        let minX = Metrics.detailPopoverBoundaryMargin - baseX
        let maxX = size.width - Metrics.detailPopoverBoundaryMargin - Metrics.detailPopoverWidth - baseX
        let minY = Metrics.detailPopoverBoundaryMargin - baseY
        let maxY = size.height - Metrics.detailPopoverBoundaryMargin - Metrics.detailPopoverHeight - baseY

        return CGSize(
            width: min(max(offset.width, min(minX, maxX)), max(minX, maxX)),
            height: min(max(offset.height, min(minY, maxY)), max(minY, maxY))
        )
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 16)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        }
    }
}

private struct EventRow: View {
    let event: AgentEvent
    let isSelected: Bool
    let toggleDetails: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(event.type.eventColor)
                .frame(width: 7, height: 7)

            Text(event.type)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            if bodyText != nil {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.34))
            }

            Spacer(minLength: 8)

            Text(toolLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? .white.opacity(0.10) : .white.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.14) : .clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            toggleDetails()
        }
    }

    private var toolLabel: String {
        if let toolName = event.toolName, !toolName.isEmpty {
            return toolName
        }
        if let detail = event.detail, !detail.isEmpty {
            return detail
        }
        return ""
    }

    private var bodyText: String? {
        if let message = event.message, !message.isEmpty {
            return message
        }
        if let detail = event.detail, !detail.isEmpty {
            return detail
        }
        return nil
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct EventDetailPopover: View {
    let event: AgentEvent
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(event.type.eventColor)
                        .frame(width: 7, height: 7)

                    Text(event.type)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(Self.timeFormatter.string(from: event.timestamp))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged(onDragChanged)
                        .onEnded { _ in onDragEnded() }
                )

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(detailText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(width: 22, height: 22)
                        .background {
                            Circle()
                                .fill(.white.opacity(0.07))
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hoverTooltip("Copy content")
            }

            if let threadID = event.threadID, !threadID.isEmpty {
                HStack(spacing: 6) {
                    Text("Thread")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(width: 38, alignment: .leading)

                    Text(threadID)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 6)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(threadID, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.52))
                            .frame(width: 18, height: 18)
                            .background {
                                Circle()
                                    .fill(.white.opacity(0.055))
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverTooltip("Copy thread ID")
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.045))
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(detailText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        }
    }

    private var detailText: String {
        if let message = event.message, !message.isEmpty {
            return message
        }
        if let detail = event.detail, !detail.isEmpty {
            return detail
        }
        return ""
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct AgentIcon: View {
    let size: CGFloat
    let symbolSize: CGFloat

    var body: some View {
        Image(systemName: "terminal")
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: max(size * 0.22, 6), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.48, blue: 0.96).opacity(0.86),
                                Color(red: 0.07, green: 0.72, blue: 0.62).opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(size * 0.22, 6), style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

private struct HookConfirmationButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isPrimary ? .black.opacity(0.82) : .white.opacity(0.72))
            .frame(width: 78, height: 26)
            .background {
                Capsule(style: .continuous)
                    .fill(isPrimary ? .white.opacity(configuration.isPressed ? 0.78 : 0.92) : .white.opacity(configuration.isPressed ? 0.12 : 0.07))
            }
    }
}

private extension String {
    var eventColor: Color {
        switch self {
        case "PreToolUse":
            return Color(red: 0.00, green: 0.62, blue: 1.00)
        case "PermissionRequest":
            return Color(red: 1.00, green: 0.58, blue: 0.08)
        case "PostToolUse", "Stop":
            return Color(red: 0.20, green: 0.92, blue: 0.38)
        case "UserPromptSubmit":
            return Color(red: 0.18, green: 0.46, blue: 1.00)
        case "SessionStart":
            return Color(red: 0.56, green: 0.58, blue: 0.62)
        default:
            return .white.opacity(0.45)
        }
    }
}
