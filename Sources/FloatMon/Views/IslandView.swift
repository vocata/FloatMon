import SwiftUI

struct IslandView: View {
    private enum Metrics {
        static let collapsedWindowDiameter: CGFloat = 68
        static let collapsedBallDiameter: CGFloat = 64
        static let collapsedIconSize: CGFloat = 38
        static let expandedSize = CGSize(width: 520, height: 460)
        static let animation = Animation.easeInOut(duration: 0.26)
        static let pressAnimation = Animation.easeOut(duration: 0.10)
        static let flipFirstHalfDuration: TimeInterval = 0.12
        static let flipSecondHalfDuration: TimeInterval = 0.16
        static let flipFirstHalfMilliseconds = 120
        static let flipSecondHalfMilliseconds = 160
        static let flipMidpointAngle: Double = 90
        static let modeBadgeSize: CGFloat = 16
        static let modeBadgeIconSize: CGFloat = 8
        static let modeBadgeOffset = CGSize(width: -3, height: -3)
        static let sortSlideTravel: CGFloat = 46
        static let sortSlideOutDuration: TimeInterval = 0.10
        static let sortSlideInDuration: TimeInterval = 0.18
        static let sortSlideOutMilliseconds = 100
        static let refreshDelayMilliseconds = 280
        static let postCloseRefreshDelayMilliseconds = 350
    }

    private let resizeWindow: (Bool) -> Void

    @State private var store: ProcessStore
    @State private var agentStore: AgentStore
    @State private var expanded = false
    @State private var monitorMode: AgentMonitorMode = .apps
    @State private var sortMode: ProcessSortMode = .cpu
    @State private var pendingForceQuitApp: AppProcess?
    @State private var focusError: String?
    @State private var togglePressed = false
    @State private var collapsedFlipAngle: Double = 0
    @State private var isCollapsedHoverSuppressed = false
    @State private var collapsedSlideOffset: CGFloat = 0
    @State private var collapsedSlideOpacity = 1.0
    @State private var isCollapsedSliding = false

    init(store: ProcessStore, agentStore: AgentStore, resizeWindow: @escaping (Bool) -> Void) {
        _store = State(initialValue: store)
        _agentStore = State(initialValue: agentStore)
        self.resizeWindow = resizeWindow
    }

    private var featuredApp: AppProcess? {
        sortMode.sorted(store.apps).first
    }

    private var featuredPressure: ResourcePressure {
        guard let featuredApp else { return .none }
        return ResourcePressure(app: featuredApp, sortMode: sortMode)
    }

    private var islandWindowSize: CGSize {
        expanded
        ? Metrics.expandedSize
        : CGSize(width: Metrics.collapsedWindowDiameter, height: Metrics.collapsedWindowDiameter)
    }

    private var islandVisualSize: CGSize {
        expanded
        ? Metrics.expandedSize
        : CGSize(width: Metrics.collapsedBallDiameter, height: Metrics.collapsedBallDiameter)
    }

    var body: some View {
        visualContent
            .frame(width: islandWindowSize.width, height: islandWindowSize.height, alignment: .center)
            .alert(
                "Force Quit \(pendingForceQuitApp?.name ?? "App")?",
                isPresented: Binding(
                    get: { pendingForceQuitApp != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingForceQuitApp = nil
                        }
                    }
                ),
                presenting: pendingForceQuitApp
            ) { app in
                Button("Cancel", role: .cancel) {
                    pendingForceQuitApp = nil
                }
                Button("Force Quit", role: .destructive) {
                    forceQuitApp(app)
                    pendingForceQuitApp = nil
                }
            } message: { app in
                Text("This will immediately terminate \(app.name). Unsaved changes may be lost.")
            }
            .alert(
                "Precise Window Focus Needs Permission",
                isPresented: Binding(
                    get: { focusError != nil },
                    set: { isPresented in
                        if !isPresented {
                            focusError = nil
                        }
                    }
                )
            ) {
                Button("Open Settings") {
                    AccessibilityPermissionService.openSettings()
                    focusError = nil
                }
                Button("OK", role: .cancel) {
                    focusError = nil
                }
            } message: {
                Text(focusError ?? "")
            }
            .onChange(of: agentStore.completionNotice?.id) { _, noticeID in
                guard noticeID != nil else { return }
                setMonitorMode(.agent)
            }
    }

    private var visualContent: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 64)

            if expanded {
                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.horizontal, 18)

                modeSwitcher
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                if monitorMode == .apps {
                    ExpandedProcessList(
                        apps: store.apps,
                        hasAccessibilityPermission: store.isAccessibilityTrusted,
                        sortMode: $sortMode,
                        openAccessibilitySettings: {
                            AccessibilityPermissionService.openSettings()
                        },
                        recheckAccessibilityPermission: {
                            store.refreshAccessibilityPermission()
                        },
                        activate: activateApp,
                        focusWindow: focusWindow,
                        closeWindow: closeWindow,
                        requestForceQuit: { pendingForceQuitApp = $0 }
                    )
                    .transition(.opacity)
                } else {
                    AgentMonitorView(
                        snapshot: agentStore.snapshot,
                        refresh: { agentStore.refreshHookStatus() },
                        selectProvider: { agentStore.selectProvider($0) },
                        registerHook: { agentStore.registerSelectedIntegration() },
                        detachHook: { agentStore.detachSelectedIntegration() }
                    )
                    .transition(.opacity)
                }
            }
        }
        .frame(width: islandVisualSize.width, height: islandVisualSize.height, alignment: .top)
        .clipShape(containerShape)
        .background {
            containerShape
                .fill(.black.opacity(0.92))
        }
        .foregroundStyle(.white)
        .scaleEffect(togglePressed ? pressedScale : 1)
        .brightness(togglePressed ? 0.045 : 0)
        .animation(Metrics.animation, value: expanded)
        .animation(Metrics.pressAnimation, value: togglePressed)
    }

    private var header: some View {
        Group {
            if expanded {
                expandedHeader
            } else {
                collapsedHeader
            }
        }
        .contentShape(Rectangle())
        .overlay(
            WindowDragBridge(
                onClick: toggleExpanded,
                onPressChanged: { togglePressed = $0 },
                onRightClick: switchCollapsedMode,
                onHorizontalSwipe: switchCollapsedModeContent
            )
        )
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(AgentMonitorMode.allCases) { mode in
                Button {
                    setMonitorMode(mode)
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(monitorMode == mode ? .white : .white.opacity(0.54))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(monitorMode == mode ? .white.opacity(0.14) : .clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.065))
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 12) {
            AppIconView(image: featuredApp?.icon, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(featuredApp?.name ?? "No open apps")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                if let featuredApp {
                    Text("\(AppFormatters.cpu(featuredApp.cpuPercent)) CPU · \(AppFormatters.memory(featuredApp.memoryBytes))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 28, height: 28)
        }
        .frame(height: 64, alignment: .center)
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(togglePressed ? 0.055 : 0))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }

    private var collapsedHeader: some View {
        Group {
            if monitorMode == .apps {
                collapsedAppHeader
            } else {
                collapsedAgentHeader
            }
        }
        .frame(width: 64, height: 64)
        .rotation3DEffect(
            .degrees(collapsedFlipAngle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
    }

    private var collapsedAppHeader: some View {
        collapsedIconFrame(
            icon: AppIconView(image: featuredApp?.icon, size: Metrics.collapsedIconSize),
            modeSystemImage: "square.grid.2x2",
            modeTint: .blue,
            status: statusDot(color: featuredPressureColor)
        )
        .offset(x: collapsedSlideOffset)
        .opacity(collapsedSlideOpacity)
        .externalHoverCard(
            title: "App · \(featuredApp?.name ?? "No open apps")",
            detailLines: collapsedAppDetailLines,
            systemImage: "app.fill",
            image: featuredApp?.icon,
            tone: featuredPressureTone,
            isEnabled: !isCollapsedHoverSuppressed
        )
    }

    private var collapsedAgentHeader: some View {
        collapsedIconFrame(
            icon: AgentIcon(provider: agentStore.snapshot.provider, size: Metrics.collapsedIconSize, fontSize: 8),
            modeSystemImage: "terminal",
            modeTint: .cyan,
            status: statusDot(color: agentStatusColor, isPulsing: agentStore.completionNotice != nil)
        )
        .offset(x: collapsedSlideOffset)
        .opacity(collapsedSlideOpacity)
        .externalHoverCard(
            title: "Agent · \(agentStore.snapshot.provider.displayName)",
            subtitle: collapsedAgentStatusLabel,
            detailLines: collapsedAgentDetailLines,
            agentProvider: agentStore.snapshot.provider,
            tone: agentStatusTone,
            onHoverChanged: { isHovering in
                agentStore.setCompletionNoticeHovered(isHovering)
            },
            isEnabled: !isCollapsedHoverSuppressed
        )
    }

    private func collapsedIconFrame<Icon: View, Status: View>(
        icon: Icon,
        modeSystemImage: String,
        modeTint: Color,
        status: Status
    ) -> some View {
        ZStack {
            icon
        }
        .frame(width: Metrics.collapsedIconSize, height: Metrics.collapsedIconSize)
        .overlay(alignment: .topLeading) {
            modeBadge(systemImage: modeSystemImage, tint: modeTint)
        }
        .overlay(alignment: .bottomTrailing) {
            status
        }
    }

    private func modeBadge(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: Metrics.modeBadgeIconSize, weight: .bold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: Metrics.modeBadgeSize, height: Metrics.modeBadgeSize)
            .background {
                Circle()
                    .fill(tint.opacity(0.86))
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.78), lineWidth: 1.5)
                    }
            }
            .offset(x: Metrics.modeBadgeOffset.width, y: Metrics.modeBadgeOffset.height)
    }

    private func statusDot(color: Color, isPulsing: Bool = false) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay {
                if isPulsing {
                    PulsingStatusRing(color: color)
                        .transition(.opacity)
                }
            }
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.92), lineWidth: 2)
            }
            .offset(x: 1, y: 1)
    }

    private var containerShape: AnyShape {
        if expanded {
            AnyShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            AnyShape(Circle())
        }
    }

    private var pressedScale: CGFloat {
        expanded ? 0.992 : 0.94
    }

    private var featuredPressureColor: Color {
        switch featuredPressure {
        case .none:
            return .gray
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private var featuredPressureTone: ExternalHoverTooltipTone {
        switch featuredPressure {
        case .none:
            return .neutral
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private var agentStatusColor: Color {
        latestAgentActivitySignal.color
    }

    private var agentStatusTone: ExternalHoverTooltipTone {
        latestAgentActivitySignal.tone
    }

    private var latestAgentActivitySignal: AgentActivitySignal {
        agentStore.snapshot.recentEvents.first?.activitySignal ?? .neutral
    }

    private var collapsedAppDetailLines: [String] {
        guard let featuredApp else {
            return []
        }

        return [
            "CPU: \(AppFormatters.cpu(featuredApp.cpuPercent))",
            "Memory: \(AppFormatters.memory(featuredApp.memoryBytes))"
        ]
    }

    private var collapsedAgentDetailLines: [String] {
        let snapshot = agentStore.snapshot
        guard snapshot.hookStatus == .registered else {
            return [collapsedAgentStatusLabel]
        }

        var lines: [String] = []

        if let thread = snapshot.currentThread {
            lines.append("Thread: \(thread.title)")
            lines.append("Workspace: \(URL(fileURLWithPath: thread.cwd).lastPathComponent)")
            lines.append("Tokens: \(AppFormatters.integer(thread.tokensUsed))")
        } else {
            lines.append("No active thread")
        }

        if let latestEvent = snapshot.recentEvents.first {
            lines.append("Latest: \(latestEvent.compactSummary)")
        }

        return lines
    }

    private var collapsedAgentStatusLabel: String {
        switch agentStore.snapshot.hookStatus {
        case .unknown:
            return "Checking \(agentStore.snapshot.provider.integrationName.lowercased())"
        case .missing:
            return "\(agentStore.snapshot.provider.integrationName) not registered"
        case .registered:
            return "\(agentStore.snapshot.provider.integrationName) active"
        case .failed:
            return "\(agentStore.snapshot.provider.integrationName) error"
        }
    }

    private func toggleExpanded() {
        let nextExpanded = !expanded
        resizeWindow(nextExpanded)
        withAnimation(Metrics.animation) {
            expanded = nextExpanded
        }
        if nextExpanded {
            refreshAfterExpansion()
        }
    }

    private func setMonitorMode(_ mode: AgentMonitorMode) {
        withAnimation(.easeInOut(duration: 0.16)) {
            monitorMode = mode
        }
        refreshForMonitorMode(mode)
    }

    private func switchCollapsedMode() {
        guard !expanded, collapsedFlipAngle == 0 else { return }

        let nextMode: AgentMonitorMode = monitorMode == .apps ? .agent : .apps
        isCollapsedHoverSuppressed = true
        withAnimation(.easeIn(duration: Metrics.flipFirstHalfDuration)) {
            collapsedFlipAngle = Metrics.flipMidpointAngle
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Metrics.flipFirstHalfMilliseconds))
            monitorMode = nextMode
            withAnimation(.easeOut(duration: Metrics.flipSecondHalfDuration)) {
                collapsedFlipAngle = 0
            }
            try? await Task.sleep(for: .milliseconds(Metrics.flipSecondHalfMilliseconds))
            isCollapsedHoverSuppressed = false
            refreshForMonitorMode(nextMode)
        }
    }

    private func switchCollapsedModeContent(_ direction: WindowSwipeDirection) {
        guard !expanded else { return }
        guard !isCollapsedSliding else { return }

        switch monitorMode {
        case .apps:
            let targetMode = CollapsedAppSortMode.target(for: direction)
            guard sortMode != targetMode else { return }
            slideCollapsedContent(direction: direction) {
                sortMode = targetMode
            }
        case .agent:
            let targetProvider = CollapsedAgentProviderMode.target(current: agentStore.selectedProvider, swipeDirection: direction)
            guard agentStore.selectedProvider != targetProvider else { return }
            slideCollapsedContent(direction: direction) {
                agentStore.selectProvider(targetProvider)
            }
        }
    }

    private func slideCollapsedContent(direction: WindowSwipeDirection, updateContent: @escaping @MainActor () -> Void) {
        isCollapsedSliding = true
        isCollapsedHoverSuppressed = true
        ExternalHoverTooltipController.hideTransiently()
        let outgoingOffset = direction == .left ? -Metrics.sortSlideTravel : Metrics.sortSlideTravel
        let incomingOffset = -outgoingOffset

        withAnimation(.easeIn(duration: Metrics.sortSlideOutDuration)) {
            collapsedSlideOffset = outgoingOffset
            collapsedSlideOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Metrics.sortSlideOutMilliseconds))
            updateContent()
            collapsedSlideOffset = incomingOffset

            withAnimation(.easeOut(duration: Metrics.sortSlideInDuration)) {
                collapsedSlideOffset = 0
                collapsedSlideOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(Int(Metrics.sortSlideInDuration * 1000)))
            isCollapsedSliding = false
            isCollapsedHoverSuppressed = false
        }
    }

    private func refreshForMonitorMode(_ mode: AgentMonitorMode) {
        if mode == .agent {
            agentStore.refreshHookStatus()
        } else {
            store.refreshAccessibilityPermission()
        }
    }

    private func refreshAfterExpansion() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Metrics.refreshDelayMilliseconds))
            guard expanded else { return }
            store.refresh()
        }
    }

    private func activateApp(_ app: AppProcess) {
        ApplicationService.activate(app) {
            store.refresh()
        }
    }

    private func forceQuitApp(_ app: AppProcess) {
        guard ApplicationService.forceQuit(app) else {
            store.refresh()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Metrics.postCloseRefreshDelayMilliseconds))
            store.refresh()
        }
    }

    private func focusWindow(_ window: AppWindowInfo, in app: AppProcess) {
        Task { @MainActor in
            let result = await WindowFocusService.focus(window: window, in: app)
            switch result {
            case .success:
                break
            case .accessibilityPermissionRequired:
                focusError = accessibilityPermissionMessage(action: "jump to", app: app)
            case .windowNotFound:
                focusError = "The target window could not be found. Refresh the list and try again."
            }
        }
    }

    private func closeWindow(_ window: AppWindowInfo, in app: AppProcess) {
        Task { @MainActor in
            let result = await WindowFocusService.close(window: window, in: app)
            switch result {
            case .success:
                try? await Task.sleep(for: .milliseconds(Metrics.postCloseRefreshDelayMilliseconds))
                store.refresh()
            case .accessibilityPermissionRequired:
                focusError = accessibilityPermissionMessage(action: "close", app: app)
            case .windowNotFound:
                focusError = "The target window could not be closed. Refresh the list and try again."
            }
        }
    }

    private func accessibilityPermissionMessage(action: String, app: AppProcess) -> String {
        "macOS requires Accessibility permission to \(action) a specific window inside \(app.name). If you already enabled it, quit FloatMon and launch the existing app again without rebuilding so macOS rechecks the same signed bundle."
    }
}

private struct PulsingStatusRing: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(color.opacity(isAnimating ? 0 : 0.72), lineWidth: 2)
            .scaleEffect(isAnimating ? 2.4 : 1.0)
            .onAppear {
                isAnimating = false
                withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
            .onDisappear {
                isAnimating = false
            }
    }
}
