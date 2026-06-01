import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindow: IslandWindow?
    private var processStore: ProcessStore?
    private var agentStore: AgentStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showIsland()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        processStore?.stop()
        agentStore?.stop()
    }

    private func showIsland() {
        if let islandWindow {
            islandWindow.orderFrontRegardless()
            return
        }

        let processStore = ProcessStore()
        self.processStore = processStore
        let agentStore = AgentStore()
        self.agentStore = agentStore
        let window = IslandWindow(processStore: processStore, agentStore: agentStore)
        islandWindow = window
        window.show()
    }
}
