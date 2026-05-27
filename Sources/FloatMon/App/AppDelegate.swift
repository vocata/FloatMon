import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindow: IslandWindow?
    private var permissionWindow: NSWindow?
    private var processStore: ProcessStore?
    private var agentStore: AgentStore?
    private var didShowHookPrompt = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        continueWhenAuthorized()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        processStore?.stop()
        agentStore?.stop()
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
        window.title = "FloatMon"
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
            maybePromptForCodexHook()
            return
        }

        let processStore = ProcessStore()
        self.processStore = processStore
        let agentStore = AgentStore()
        self.agentStore = agentStore
        let window = IslandWindow(processStore: processStore, agentStore: agentStore)
        islandWindow = window
        window.show()
        maybePromptForCodexHook()
    }

    private func maybePromptForCodexHook() {
        guard !didShowHookPrompt,
              let agentStore,
              agentStore.shouldPromptForCodexHook else {
            return
        }

        didShowHookPrompt = true

        let alert = NSAlert()
        alert.messageText = "Register Codex monitoring hook?"
        alert.informativeText = "FloatMon can monitor Codex live events by adding a hook command to ~/.codex/hooks.json. The current hooks file will be backed up before change."
        alert.addButton(withTitle: "Register")
        alert.addButton(withTitle: "Skip")

        if alert.runModal() == .alertFirstButtonReturn {
            agentStore.registerCodexHook()
        } else {
            agentStore.declineHookRegistration()
        }
    }
}
