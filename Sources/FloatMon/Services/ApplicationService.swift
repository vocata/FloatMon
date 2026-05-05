import AppKit

enum ApplicationService {
    @MainActor
    static func activate(_ app: AppProcess, completion: (() -> Void)? = nil) {
        activateRunningInstance(app)

        guard let bundleURL = app.bundleURL ?? bundleURL(for: app) else {
            completion?()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                completion?()
            }
        }
    }

    @MainActor
    @discardableResult
    static func activateRunningInstance(_ app: AppProcess) -> Bool {
        guard let runningApp = NSRunningApplication(processIdentifier: app.id) else {
            return false
        }

        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows])
        return true
    }

    @MainActor
    @discardableResult
    static func forceQuit(_ app: AppProcess) -> Bool {
        guard let runningApp = NSRunningApplication(processIdentifier: app.id) else {
            return false
        }

        return runningApp.forceTerminate()
    }

    private static func bundleURL(for app: AppProcess) -> URL? {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return nil
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}
