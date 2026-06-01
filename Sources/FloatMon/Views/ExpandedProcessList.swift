import AppKit
import SwiftUI

struct ExpandedProcessList: View {
    let apps: [AppProcess]
    let hasAccessibilityPermission: Bool
    @Binding var sortMode: ProcessSortMode
    let openAccessibilitySettings: () -> Void
    let recheckAccessibilityPermission: () -> Bool
    let activate: (AppProcess) -> Void
    let focusWindow: (AppWindowInfo, AppProcess) -> Void
    let closeWindow: (AppWindowInfo, AppProcess) -> Void
    let requestForceQuit: (AppProcess) -> Void

    @State private var expandedAppIDs: Set<pid_t> = []
    @State private var searchText = ""
    @State private var permissionMessage: String?

    private var sortedApps: [AppProcess] {
        sortMode.sorted(apps)
    }

    private var commandMatches: [CommandMatch] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return sortedApps.flatMap { app -> [CommandMatch] in
            var matches: [CommandMatch] = []
            if let score = appMatchScore(app, query: query) {
                matches.append(
                    CommandMatch(
                        id: "app-\(app.id)",
                        title: app.name,
                        subtitle: app.bundleIdentifier ?? "pid \(app.id)",
                        app: app,
                        window: nil,
                        score: score
                    )
                )
            }

            matches.append(
                contentsOf: app.windows
                    .compactMap { window in
                        let titleScore = fuzzyScore(query, in: window.title)
                        let appScore = appMatchScore(app, query: query).map { $0 - 8 }
                        guard let score = [titleScore, appScore].compactMap({ $0 }).max() else {
                            return nil
                        }

                        return CommandMatch(
                            id: "window-\(app.id)-\(window.id)",
                            title: window.title,
                            subtitle: app.name,
                            app: app,
                            window: window,
                            score: score
                        )
                    }
            )
            return matches
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        .prefix(9)
        .map { $0 }
    }

    private var expandableAppIDs: Set<pid_t> {
        Set(apps.filter { !$0.windows.isEmpty }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if hasAccessibilityPermission {
                CommandSearchField(text: $searchText)
                    .padding(.horizontal, 18)

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(sortedApps) { app in
                                processSection(for: app)
                            }
                        }
                        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: sortMode)
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: expandedAppIDs)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.automatic)
                } else {
                    CommandResultList(
                        matches: commandMatches,
                        activate: activate,
                        focusWindow: focusWindow,
                        closeWindow: closeWindow,
                        requestForceQuit: requestForceQuit
                    )
                    .padding(.horizontal, 12)
                }
            } else {
                accessibilityPermissionContent
                    .transition(.opacity)
            }
        }
        .onChange(of: expandableAppIDs) { _, ids in
            expandedAppIDs.formIntersection(ids)
        }
        .onChange(of: hasAccessibilityPermission) { _, isTrusted in
            if isTrusted {
                permissionMessage = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Open Apps")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if hasAccessibilityPermission {
                Text("\(apps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                SortModeControl(selection: $sortMode)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var accessibilityPermissionContent: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.10))

                Image(systemName: "accessibility")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .frame(width: 42, height: 42)

            VStack(spacing: 4) {
                Text("Accessibility Permission Required")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                Text("Authorize FloatMon to inspect windows, focus apps, and close app windows.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 360)
            }

            if let permissionMessage {
                Text(permissionMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 8) {
                Button {
                    openAccessibilitySettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .buttonStyle(AppPermissionButtonStyle(isPrimary: true))

                Button {
                    if recheckAccessibilityPermission() {
                        permissionMessage = nil
                    } else {
                        permissionMessage = "Permission is still missing. Enable FloatMon in Accessibility, then recheck."
                    }
                } label: {
                    Label("Recheck", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AppPermissionButtonStyle(isPrimary: false))
            }

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
    }

    private func appMatchScore(_ app: AppProcess, query: String) -> Int? {
        [
            fuzzyScore(query, in: app.name),
            app.bundleIdentifier.flatMap { fuzzyScore(query, in: $0) }.map { $0 - 4 }
        ]
        .compactMap { $0 }
        .max()
    }

    private func processSection(for app: AppProcess) -> some View {
        let isWindowListVisible = expandedAppIDs.contains(app.id) && !app.windows.isEmpty

        return VStack(spacing: 4) {
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

    private func toggleWindows(for app: AppProcess) {
        guard !app.windows.isEmpty else { return }

        if expandedAppIDs.contains(app.id) {
            expandedAppIDs.remove(app.id)
        } else {
            expandedAppIDs.insert(app.id)
        }
    }
}

private struct CommandSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))

            SearchTextField(text: $text, placeholder: "Search apps and windows")
                .frame(height: 22)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .hoverTooltip("Clear")
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = CursorAwareTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 12, weight: .medium)
        textField.textColor = .white
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.48),
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }
    }
}

private struct AppPermissionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(isPrimary ? 0.90 : 0.72))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(.white.opacity(isPrimary ? 0.14 : 0.08))
            }
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private final class CursorAwareTextField: NSTextField {
    private var trackingArea: NSTrackingArea?
    private var mouseMonitor: Any?

    deinit {
        removeMouseMonitor()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        restoreArrowCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCursor(for: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeMouseMonitor()
            restoreArrowCursor()
        } else {
            installMouseMonitor()
        }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.updateCursor(for: event)
            return event
        }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else { return }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }

    private func updateCursor(for event: NSEvent) {
        guard let window, event.window === window else {
            restoreArrowCursor()
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            NSCursor.iBeam.set()
        } else {
            restoreArrowCursor()
        }
    }

    private func restoreArrowCursor() {
        NSCursor.arrow.set()
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            let location = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard !self.bounds.contains(location) else { return }
            NSCursor.arrow.set()
        }
    }
}

private struct CommandResultList: View {
    let matches: [CommandMatch]
    let activate: (AppProcess) -> Void
    let focusWindow: (AppWindowInfo, AppProcess) -> Void
    let closeWindow: (AppWindowInfo, AppProcess) -> Void
    let requestForceQuit: (AppProcess) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if matches.isEmpty {
                    Text("No matching apps or windows")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(matches) { match in
                        CommandResultRow(
                            match: match,
                            activate: activate,
                            focusWindow: focusWindow,
                            closeWindow: closeWindow,
                            requestForceQuit: requestForceQuit
                        )
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.automatic)
    }
}

private struct CommandResultRow: View {
    let match: CommandMatch
    let activate: (AppProcess) -> Void
    let focusWindow: (AppWindowInfo, AppProcess) -> Void
    let closeWindow: (AppWindowInfo, AppProcess) -> Void
    let requestForceQuit: (AppProcess) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(image: match.app.icon, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(match.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let window = match.window {
                CommandIconButton(systemName: "rectangle.on.rectangle", help: "Show") {
                    focusWindow(window, match.app)
                }
                CommandIconButton(systemName: "xmark", help: "Close") {
                    closeWindow(window, match.app)
                }
            } else {
                CommandIconButton(systemName: "arrow.up.forward.app", help: "Open") {
                    activate(match.app)
                }
                CommandIconButton(systemName: "xmark", help: "Quit") {
                    requestForceQuit(match.app)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.11 : 0.06))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if let window = match.window {
                focusWindow(window, match.app)
            } else {
                activate(match.app)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct CommandIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.72))
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.16 : 0.08))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverTooltip(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct CommandMatch: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let app: AppProcess
    let window: AppWindowInfo?
    let score: Int
}

private func fuzzyScore(_ query: String, in candidate: String) -> Int? {
    let query = query.normalizedForSearch
    let candidate = candidate.normalizedForSearch
    guard !query.isEmpty, !candidate.isEmpty else { return nil }

    if candidate == query {
        return 120
    }

    if candidate.hasPrefix(query) {
        return 100 - min(candidate.count - query.count, 20)
    }

    if candidate.contains(query) {
        return 82 - min(candidate.count - query.count, 24)
    }

    guard let subsequenceScore = fuzzySubsequenceScore(query, in: candidate) else {
        return nil
    }

    return subsequenceScore
}

private func fuzzySubsequenceScore(_ query: String, in candidate: String) -> Int? {
    let queryCharacters = Array(query)
    let candidateCharacters = Array(candidate)
    var queryIndex = 0
    var lastMatchIndex: Int?
    var score = 54

    for (candidateIndex, character) in candidateCharacters.enumerated() {
        guard queryIndex < queryCharacters.count else { break }
        guard character == queryCharacters[queryIndex] else { continue }

        if let lastMatchIndex {
            score -= min(candidateIndex - lastMatchIndex - 1, 6)
        } else {
            score -= min(candidateIndex, 12)
        }

        lastMatchIndex = candidateIndex
        queryIndex += 1
    }

    guard queryIndex == queryCharacters.count else { return nil }
    score += min(queryCharacters.count * 4, 28)
    return max(score, 1)
}

private extension String {
    var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}
