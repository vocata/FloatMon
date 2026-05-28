import Foundation
import Observation

@Observable
@MainActor
final class AgentStore {
    var snapshot = AgentSnapshot.empty

    private let paths: CodexPaths
    private let reader: CodexSnapshotReader
    private let registrationService: CodexHookRegistrationService
    private let executablePath: String
    private var hookStatus: AgentHookStatus = .unknown
    private var isRefreshing = false
    private var refreshTask: Task<Void, Never>?
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
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(force: Bool = false) {
        if isRefreshing {
            guard force else { return }
            refreshTask?.cancel()
            isRefreshing = false
        }
        isRefreshing = true

        let reader = reader
        let hookStatus = hookStatus
        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                reader.readSnapshot(hookStatus: hookStatus)
            }.value

            guard let self, !Task.isCancelled else { return }
            self.snapshot = snapshot
            self.isRefreshing = false
        }
    }

    func refreshHookStatus() {
        if registrationService.isRegistered(executablePath: executablePath) {
            hookStatus = .registered
        } else {
            hookStatus = .missing
        }
        refresh(force: true)
    }

    func declineHookRegistration() {
        hookStatus = .declined
        refresh()
    }

    func registerCodexHook() {
        do {
            _ = try registrationService.register(executablePath: executablePath)
            hookStatus = .registered
        } catch {
            hookStatus = .failed(error.localizedDescription)
        }
        refresh()
    }
}
