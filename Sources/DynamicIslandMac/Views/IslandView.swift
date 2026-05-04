import AppKit
import SwiftUI

struct IslandView: View {
    private enum Metrics {
        static let collapsedWindowDiameter: CGFloat = 68
        static let collapsedBallDiameter: CGFloat = 64
        static let expandedSize = CGSize(width: 520, height: 390)
        static let animation = Animation.easeInOut(duration: 0.26)
        static let pressAnimation = Animation.easeOut(duration: 0.10)
        static let refreshDelayMilliseconds = 280
    }

    @State var store: ProcessStore
    @State private var expanded = false
    @State private var sortMode: ProcessSortMode = .cpu
    @State private var pendingForceQuitApp: AppProcess?
    @State private var focusError: String?
    @State private var togglePressed = false

    private var activeApp: AppProcess? {
        store.apps.first(where: \.isActive) ?? store.apps.first
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
                    openAccessibilitySettings()
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
            collapsedContent
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

    private func toggleExpanded() {
        let nextExpanded = !expanded
        currentPanel?.resize(expanded: nextExpanded)
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

    private var collapsedContent: some View {
        Group {
            if expanded {
                HStack(spacing: 12) {
                    AppIconView(image: activeApp?.icon, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeApp?.name ?? "No active apps")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)

                        if let activeApp {
                            Text("\(AppFormatters.cpu(activeApp.cpuPercent)) CPU · \(AppFormatters.memory(activeApp.memoryBytes))")
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
            } else {
                ZStack(alignment: .bottomTrailing) {
                    AppIconView(image: activeApp?.icon, size: 38)

                    Circle()
                        .fill(activeApp == nil ? .gray : .green)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle()
                                .stroke(.black.opacity(0.92), lineWidth: 2)
                        }
                        .offset(x: 1, y: 1)
                }
                .frame(width: 64, height: 64)
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

    private var currentPanel: IslandWindow? {
        NSApp.windows.first { $0 is IslandWindow } as? IslandWindow
    }

    private func activateApp(_ app: AppProcess) {
        if let runningApp = NSRunningApplication(processIdentifier: app.id) {
            runningApp.unhide()
            runningApp.activate(options: [.activateAllWindows])
        }

        guard let bundleURL = app.bundleURL ?? bundleURL(for: app) else {
            store.refresh()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                store.refresh()
            }
        }
    }

    private func bundleURL(for app: AppProcess) -> URL? {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return nil
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    private func forceQuitApp(_ app: AppProcess) {
        guard let runningApp = NSRunningApplication(processIdentifier: app.id) else {
            store.refresh()
            return
        }

        runningApp.forceTerminate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
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
                focusError = "macOS requires Accessibility permission to jump to a specific window inside \(app.name). If you already enabled it, quit DynamicIslandMac and launch the existing app again without rebuilding so macOS rechecks the same signed bundle."
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
                try? await Task.sleep(for: .milliseconds(350))
                store.refresh()
            case .accessibilityPermissionRequired:
                focusError = "macOS requires Accessibility permission to close a specific window inside \(app.name). If you already enabled it, quit DynamicIslandMac and launch the existing app again without rebuilding so macOS rechecks the same signed bundle."
            case .windowNotFound:
                focusError = "The target window could not be closed. Refresh the list and try again."
            }
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct CameraCapsule: View {
    var body: some View {
        Capsule()
            .fill(.black)
            .frame(width: 78, height: 25)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 9, height: 9)
                    .padding(.trailing, 11)
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct ExpandedProcessList: View {
    let apps: [AppProcess]
    @Binding var sortMode: ProcessSortMode
    let activate: (AppProcess) -> Void
    let focusWindow: (AppWindowInfo, AppProcess) -> Void
    let closeWindow: (AppWindowInfo, AppProcess) -> Void
    let requestForceQuit: (AppProcess) -> Void
    @State private var expandedAppIDs: Set<pid_t> = []

    private var sortedApps: [AppProcess] {
        sortMode.sorted(apps)
    }

    private var expandableAppIDs: Set<pid_t> {
        Set(apps.filter { !$0.windows.isEmpty }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Open Apps")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(apps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                SortModeControl(selection: $sortMode)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sortedApps) { app in
                        let isWindowListVisible = expandedAppIDs.contains(app.id) && !app.windows.isEmpty

                        VStack(spacing: 4) {
                            ProcessRow(
                                app: app,
                                isExpanded: isWindowListVisible,
                                toggleWindows: { toggleWindows(for: app) },
                                activate: { activate(app) },
                                requestForceQuit: { requestForceQuit(app) }
                            )

                            if isWindowListVisible {
                                WindowList(
                                    windows: app.windows,
                                    appIcon: app.icon,
                                    focusWindow: {
                                        focusWindow($0, app)
                                    },
                                    closeWindow: {
                                        closeWindow($0, app)
                                    }
                                )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.9), value: sortMode)
                .animation(.spring(response: 0.28, dampingFraction: 0.9), value: expandedAppIDs)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
        }
        .onChange(of: expandableAppIDs) { _, ids in
            expandedAppIDs.formIntersection(ids)
        }
    }

    private func toggleWindows(for app: AppProcess) {
        guard !app.windows.isEmpty else { return }

        if expandedAppIDs.contains(app.id) {
            expandedAppIDs.remove(app.id)
        } else {
            expandedAppIDs.insert(app.id)
        }
    }
}

private struct SortModeControl: View {
    @Binding var selection: ProcessSortMode

    private let itemWidth: CGFloat = 58
    private let itemHeight: CGFloat = 24
    private let spacing: CGFloat = 2
    private let padding: CGFloat = 3

    private var selectionIndex: Int {
        ProcessSortMode.allCases.firstIndex(of: selection) ?? 0
    }

    private var controlWidth: CGFloat {
        CGFloat(ProcessSortMode.allCases.count) * itemWidth +
        CGFloat(ProcessSortMode.allCases.count - 1) * spacing +
        padding * 2
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
                .frame(width: itemWidth, height: itemHeight)
                .offset(x: padding + CGFloat(selectionIndex) * (itemWidth + spacing))
                .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.14), value: selection)

            HStack(spacing: spacing) {
                ForEach(ProcessSortMode.allCases) { mode in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.14)) {
                            selection = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selection == mode ? .black : .white.opacity(0.68))
                            .frame(width: itemWidth, height: itemHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(padding)
        }
        .frame(width: controlWidth, height: itemHeight + padding * 2)
        .background {
            Capsule()
                .fill(.white.opacity(0.1))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct ProcessRow: View {
    let app: AppProcess
    let isExpanded: Bool
    let toggleWindows: () -> Void
    let activate: () -> Void
    let requestForceQuit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: app.icon, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if app.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(app.bundleIdentifier ?? "pid \(app.id)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(AppFormatters.cpu(app.cpuPercent))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(AppFormatters.memory(app.memoryBytes))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .monospacedDigit()
            .frame(width: 86, alignment: .trailing)

            if !app.windows.isEmpty {
                HStack(spacing: 3) {
                    Text("\(app.windows.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.white.opacity(0.56))
                .frame(width: 30, alignment: .center)
            } else {
                Color.clear
                    .frame(width: 30)
            }

            Button {
                requestForceQuit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.86 : 0.56))
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(.white.opacity(isHovering ? 0.14 : 0.08))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Force quit \(app.name)")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowBackground)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: toggleWindows)
        .onTapGesture(count: 2, perform: activate)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(app.windows.isEmpty ? "Double-click to open \(app.name)" : "Click to show windows, double-click to open \(app.name)")
    }

    private var rowBackground: Color {
        if app.isActive {
            return .white.opacity(isHovering ? 0.18 : 0.14)
        }

        return .white.opacity(isHovering ? 0.11 : 0.07)
    }
}

private struct WindowList: View {
    let windows: [AppWindowInfo]
    let appIcon: NSImage?
    let focusWindow: (AppWindowInfo) -> Void
    let closeWindow: (AppWindowInfo) -> Void
    @State private var hoveringWindowID: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: 2)
                .padding(.top, 4)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(windows) { window in
                    HStack(spacing: 8) {
                        AppIconView(image: appIcon, size: 16)

                        Text(window.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Button {
                            closeWindow(window)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white.opacity(hoveringWindowID == window.id ? 0.76 : 0.42))
                                .frame(width: 18, height: 18)
                                .background {
                                    Circle()
                                        .fill(.white.opacity(hoveringWindowID == window.id ? 0.12 : 0.06))
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Close \(window.title)")
                    }
                    .frame(height: 28)
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(backgroundOpacity(for: window))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture(count: 2) {
                        focusWindow(window)
                    }
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) {
                            hoveringWindowID = hovering ? window.id : nil
                        }
                    }
                    .help("Double-click to show \(window.title)")
                }
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 18)
    }

    private func backgroundOpacity(for window: AppWindowInfo) -> Color {
        if hoveringWindowID == window.id {
            return .white.opacity(0.075)
        }

        return .white.opacity(0.035)
    }
}

private struct AppIconView: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .padding(6)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
