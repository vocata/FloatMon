import SwiftUI

struct IslandView: View {
    private enum Metrics {
        static let collapsedWindowDiameter: CGFloat = 68
        static let collapsedBallDiameter: CGFloat = 64
        static let expandedSize = CGSize(width: 520, height: 390)
        static let animation = Animation.easeInOut(duration: 0.26)
        static let pressAnimation = Animation.easeOut(duration: 0.10)
        static let refreshDelayMilliseconds = 280
        static let postCloseRefreshDelayMilliseconds = 350
    }

    private let resizeWindow: (Bool) -> Void

    @State private var store: ProcessStore
    @State private var expanded = false
    @State private var sortMode: ProcessSortMode = .cpu
    @State private var pendingForceQuitApp: AppProcess?
    @State private var focusError: String?
    @State private var togglePressed = false

    init(store: ProcessStore, resizeWindow: @escaping (Bool) -> Void) {
        _store = State(initialValue: store)
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

                ExpandedProcessList(
                    apps: store.apps,
                    sortMode: $sortMode,
                    activate: activateApp,
                    focusWindow: focusWindow,
                    closeWindow: closeWindow,
                    requestForceQuit: { pendingForceQuitApp = $0 }
                )
                .transition(.opacity)
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
        ZStack(alignment: .bottomTrailing) {
            AppIconView(image: featuredApp?.icon, size: 38)

            Circle()
                .fill(featuredPressureColor)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.92), lineWidth: 2)
                }
                .offset(x: 1, y: 1)
        }
        .frame(width: 64, height: 64)
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
