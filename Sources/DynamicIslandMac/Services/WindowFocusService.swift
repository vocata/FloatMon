import AppKit
import ApplicationServices

enum WindowFocusResult {
    case success
    case accessibilityPermissionRequired
    case windowNotFound
}

enum WindowFocusService {
    @MainActor
    static func activate(app: AppProcess) {
        if let runningApp = NSRunningApplication(processIdentifier: app.id) {
            runningApp.unhide()
            runningApp.activate(options: [.activateAllWindows])
        }
    }

    @MainActor
    @discardableResult
    static func focus(window: AppWindowInfo, in app: AppProcess) -> WindowFocusResult {
        guard AccessibilityPermissionService.isTrusted(prompt: false) else {
            activate(app: app)
            return .accessibilityPermissionRequired
        }

        guard let axWindow = axWindow(for: window, pid: app.id) else {
            activate(app: app)
            return .windowNotFound
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return .success
    }

    private static func axWindow(for window: AppWindowInfo, pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        if !window.titleIsFallback, let match = windows.first(where: { titleMatches(axTitle($0), window.title) }) {
            return match
        }

        if let match = windows.first(where: { axWindowID($0) == window.id }) {
            return match
        }

        return nil
    }

    private static func axWindowID(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXWindowNumber" as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private static func axTitle(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private static func titleMatches(_ axTitle: String?, _ sampledTitle: String) -> Bool {
        guard let axTitle else {
            return false
        }

        let normalizedAXTitle = normalizeTitle(axTitle)
        let normalizedSampledTitle = normalizeTitle(sampledTitle)

        guard !normalizedAXTitle.isEmpty, !normalizedSampledTitle.isEmpty else {
            return false
        }

        return normalizedAXTitle == normalizedSampledTitle ||
        normalizedAXTitle.contains(normalizedSampledTitle) ||
        normalizedSampledTitle.contains(normalizedAXTitle)
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
