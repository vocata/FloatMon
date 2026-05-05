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
        ApplicationService.activateRunningInstance(app)
    }

    @MainActor
    @discardableResult
    static func focus(window: AppWindowInfo, in app: AppProcess) async -> WindowFocusResult {
        guard AccessibilityPermissionService.isTrusted(prompt: false) else {
            activate(app: app)
            return .accessibilityPermissionRequired
        }

        activate(app: app)
        try? await Task.sleep(for: .milliseconds(90))

        let appElement = AXUIElementCreateApplication(app.id)
        guard let axWindow = axWindow(for: window, appName: app.name, appElement: appElement) else {
            activate(app: app)
            return .windowNotFound
        }

        focus(axWindow: axWindow, appElement: appElement)
        try? await Task.sleep(for: .milliseconds(80))
        focus(axWindow: axWindow, appElement: appElement)

        return isFocused(axWindow: axWindow, appElement: appElement, expectedFrame: window.frame)
        ? .success
        : .windowNotFound
    }

    @MainActor
    @discardableResult
    static func close(window: AppWindowInfo, in app: AppProcess) async -> WindowFocusResult {
        guard AccessibilityPermissionService.isTrusted(prompt: false) else {
            activate(app: app)
            return .accessibilityPermissionRequired
        }

        activate(app: app)
        try? await Task.sleep(for: .milliseconds(90))

        let appElement = AXUIElementCreateApplication(app.id)
        guard let axWindow = axWindow(for: window, appName: app.name, appElement: appElement) else {
            return .windowNotFound
        }

        focus(axWindow: axWindow, appElement: appElement)
        try? await Task.sleep(for: .milliseconds(80))
        guard let closeButton = closeButton(for: axWindow) else {
            return .windowNotFound
        }

        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
        ? .success
        : .windowNotFound
    }

    private static func axWindow(
        for window: AppWindowInfo,
        appName: String,
        appElement: AXUIElement
    ) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        let windowsWithIDs = windows.compactMap { element -> (element: AXUIElement, id: Int)? in
            guard let id = axWindowID(element) else { return nil }
            return (element, id)
        }
        if let match = windowsWithIDs.first(where: { $0.id == window.id })?.element {
            return match
        }

        if !windowsWithIDs.isEmpty {
            return nil
        }

        let titleMatches = windows.filter { titleExactlyMatches(axTitle($0), window.title, appName: appName) }
        if titleMatches.count == 1 {
            return titleMatches[0]
        }

        let frameMatchedWindows = windows.filter { frameMatches(axFrame($0), window.frame) }
        if frameMatchedWindows.count == 1 {
            return frameMatchedWindows[0]
        }

        if
            frameMatchedWindows.count > 1,
            let titleMatch = frameMatchedWindows.first(where: { titleExactlyMatches(axTitle($0), window.title, appName: appName) })
        {
            return titleMatch
        }

        if windows.count == 1, let match = windows.first {
            return match
        }

        let fuzzyTitleMatches = windows.filter { titleFuzzilyMatches(axTitle($0), window.title, appName: appName) }
        if fuzzyTitleMatches.count == 1 {
            return fuzzyTitleMatches[0]
        }

        return nil
    }

    private static func focus(axWindow: AXUIElement, appElement: AXUIElement) {
        AXUIElementSetAttributeValue(
            appElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementSetAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        )
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)

        AXUIElementSetAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            axWindow
        )
        AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            axWindow
        )
        AXUIElementSetAttributeValue(
            axWindow,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementSetAttributeValue(
            axWindow,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private static func closeButton(for axWindow: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axWindow,
            kAXCloseButtonAttribute as CFString,
            &value
        )

        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func isFocused(
        axWindow: AXUIElement,
        appElement: AXUIElement,
        expectedFrame: CGRect
    ) -> Bool {
        focusedWindow(appElement, attribute: kAXFocusedWindowAttribute as CFString)
            .map { sameWindow($0, axWindow) || frameMatches(axFrame($0), expectedFrame) } == true ||
        focusedWindow(appElement, attribute: kAXMainWindowAttribute as CFString)
            .map { sameWindow($0, axWindow) || frameMatches(axFrame($0), expectedFrame) } == true
    }

    private static func focusedWindow(_ appElement: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, attribute, &value)
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func sameWindow(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
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

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard
            let position = axPoint(element, attribute: kAXPositionAttribute as CFString),
            let size = axSize(element, attribute: kAXSizeAttribute as CFString)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func axPoint(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        var point = CGPoint.zero
        let axValue = value as! AXValue
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func axSize(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        var size = CGSize.zero
        let axValue = value as! AXValue
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
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

    private static func frameMatches(_ axFrame: CGRect?, _ sampledFrame: CGRect) -> Bool {
        guard let axFrame else {
            return false
        }

        let tolerance: CGFloat = 12
        return abs(axFrame.midX - sampledFrame.midX) <= tolerance &&
        abs(axFrame.midY - sampledFrame.midY) <= tolerance &&
        abs(axFrame.width - sampledFrame.width) <= tolerance &&
        abs(axFrame.height - sampledFrame.height) <= tolerance
    }

    private static func titleExactlyMatches(_ axTitle: String?, _ sampledTitle: String, appName: String) -> Bool {
        guard let axTitle else {
            return false
        }

        let axVariants = normalizedTitleVariants(axTitle, appName: appName)
        let sampledVariants = normalizedTitleVariants(sampledTitle, appName: appName)
        return !axVariants.isDisjoint(with: sampledVariants)
    }

    private static func titleFuzzilyMatches(_ axTitle: String?, _ sampledTitle: String, appName: String) -> Bool {
        guard let axTitle else {
            return false
        }

        let axVariants = normalizedTitleVariants(axTitle, appName: appName)
        let sampledVariants = normalizedTitleVariants(sampledTitle, appName: appName)

        for axVariant in axVariants where !axVariant.isEmpty {
            for sampledVariant in sampledVariants where !sampledVariant.isEmpty {
                if axVariant.count >= 8,
                   sampledVariant.count >= 8,
                   (axVariant.contains(sampledVariant) || sampledVariant.contains(axVariant)) {
                    return true
                }
            }
        }

        return false
    }

    private static func normalizedTitleVariants(_ title: String, appName: String) -> Set<String> {
        let normalized = normalizeTitle(title)
        guard !normalized.isEmpty else {
            return []
        }

        var variants: Set<String> = [normalized]
        let appSuffix = normalizeTitle(appName)
        for separator in [" - ", " – ", " — "] {
            let suffix = separator + appSuffix
            if normalized.hasSuffix(suffix) {
                variants.insert(String(normalized.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return variants
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
