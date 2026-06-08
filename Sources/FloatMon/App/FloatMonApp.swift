import SwiftUI

@main
struct FloatMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = CodexHookWriter.runIfRequested()
        _ = OpenCodeHookWriter.runIfRequested()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
