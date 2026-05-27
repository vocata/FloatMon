import Foundation
import Observation

@Observable
@MainActor
final class AgentStore {
    var snapshot = AgentSnapshot.empty
    var shouldPromptForCodexHook = false

    private let paths: CodexPaths
    private let reader: CodexSnapshotReader
    private let registrationService: CodexHookRegistrationService
    private let executablePath: String
    private var hookStatus: AgentHookStatus = .unknown
    private var timer: Timer?

    init(
        paths: CodexPaths = CodexPaths(),
        refreshInterval: TimeInterval = 2,
        executablePath: String = Bundle.main.executablePath ?? "/Applications/FloatMon.app/Contents/MacOS/FloatMon"
    ) {
        self.paths = paths
        self.reader = CodexSnapshotReader(paths: paths)
        self.registrationService = CodexHookRegistrationService(paths: paths)
        self.executablePath = executablePath
        refreshHookStatus()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        snapshot = reader.readSnapshot(hookStatus: hookStatus)
    }

    func refreshHookStatus() {
        if registrationService.isRegistered(executablePath: executablePath) {
            hookStatus = .registered
            shouldPromptForCodexHook = false
        } else {
            hookStatus = .missing
            shouldPromptForCodexHook = true
        }
    }

    func declineHookRegistration() {
        hookStatus = .declined
        shouldPromptForCodexHook = false
        refresh()
    }

    func registerCodexHook() {
        do {
            _ = try registrationService.register(executablePath: executablePath)
            hookStatus = .registered
            shouldPromptForCodexHook = false
        } catch {
            hookStatus = .failed(error.localizedDescription)
            shouldPromptForCodexHook = false
        }
        refresh()
    }
}
