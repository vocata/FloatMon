import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindow: IslandWindow?
    private var permissionWindow: NSWindow?
    private var processStore: ProcessStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        continueWhenAuthorized()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func continueWhenAuthorized() {
        if AccessibilityPermissionService.isTrusted(prompt: false) {
            showIsland()
        } else {
            showPermissionWindow()
        }
    }

    private func showPermissionWindow() {
        if let permissionWindow {
            permissionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = AccessibilityPermissionView(
            openSettings: {
                AccessibilityPermissionService.openSettings()
            },
            recheckPermission: {
                AccessibilityPermissionService.isTrusted(prompt: false)
            },
            continueToApp: { [weak self] in
                self?.showIsland()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DynamicIslandMac"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        permissionWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showIsland() {
        permissionWindow?.close()
        permissionWindow = nil

        if let islandWindow {
            islandWindow.orderFrontRegardless()
            return
        }

        let processStore = ProcessStore()
        self.processStore = processStore
        let window = IslandWindow(processStore: processStore)
        islandWindow = window
        window.show()
    }
}
