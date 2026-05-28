import SwiftUI

struct IslandView: View {
    private enum Metrics {
        static let collapsedWindowDiameter: CGFloat = 68
        static let collapsedBallDiameter: CGFloat = 64
        static let expandedSize = CGSize(width: 520, height: 460)
        static let animation = Animation.easeInOut(duration: 0.26)
        static let pressAnimation = Animation.easeOut(duration: 0.10)
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
                        sortMode: $sortMode,
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
                        registerHook: { agentStore.registerCodexHook() }
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
                onPressChanged: { togglePressed = $0 }
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
    }

    private var collapsedAppHeader: some View {
        ZStack(alignment: .bottomTrailing) {
            AppIconView(image: featuredApp?.icon, size: 38)
            statusDot(color: featuredPressureColor)
        }
        .externalHoverCard(
            title: featuredApp?.name ?? "No open apps",
            subtitle: collapsedAppSubtitle,
            systemImage: "app.fill",
            image: featuredApp?.icon,
            tone: featuredPressureTone
        )
    }

    private var collapsedAgentHeader: some View {
        ZStack(alignment: .bottomTrailing) {
            AgentIcon(provider: agentStore.snapshot.provider, size: 32, fontSize: 8)
                .frame(width: 38, height: 38)

            statusDot(color: agentStatusColor)
        }
        .externalHoverCard(
            title: agentStore.snapshot.provider.displayName,
            subtitle: agentStore.snapshot.hookStatus.label,
            detailLines: collapsedAgentDetailLines,
            agentProvider: agentStore.snapshot.provider,
            tone: agentStatusTone
        )
    }

    private func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
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
        switch agentStore.snapshot.latestEventType {
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
            return .gray
        }
    }

    private var agentStatusTone: ExternalHoverTooltipTone {
        switch agentStore.snapshot.latestEventType {
        case "PreToolUse":
            return .cyan
        case "PermissionRequest":
            return .orange
        case "PostToolUse", "Stop":
            return .green
        case "UserPromptSubmit":
            return .blue
        case "SessionStart":
            return .neutral
        default:
            return .neutral
        }
    }

    private var collapsedAppSubtitle: String? {
        guard let featuredApp else {
            return nil
        }

        return "\(AppFormatters.cpu(featuredApp.cpuPercent)) CPU · \(AppFormatters.memory(featuredApp.memoryBytes))"
    }

    private var collapsedAgentDetailLines: [String] {
        let snapshot = agentStore.snapshot
        var lines: [String] = []

        if let thread = snapshot.currentThread {
            lines.append("Thread: \(thread.title)")
            lines.append("Workspace: \(URL(fileURLWithPath: thread.cwd).lastPathComponent)")
            lines.append("Tokens: \(AppFormatters.integer(thread.tokensUsed))")
        } else {
            lines.append("No active thread")
        }

        if let latestEventType = snapshot.latestEventType {
            lines.append("Latest: \(latestEventType)")
        }

        return lines
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
        if mode == .agent {
            agentStore.refreshHookStatus()
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
