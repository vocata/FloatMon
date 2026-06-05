import Foundation
import Observation

@Observable
@MainActor
final class AgentStore {
    var snapshot = AgentSnapshot.empty
    var completionNotice: AgentCompletionNotice?
    var selectedProvider: AgentProvider = .codex

    private let integrations: [AgentProvider: any AgentIntegration]
    private let executablePath: String
    private var hookStatuses: [AgentProvider: AgentHookStatus] = [:]
    private var snapshotsByProvider: [AgentProvider: AgentSnapshot] = [:]
    private var isRefreshing = false
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var completionNotifier = AgentCompletionNotifier()
    private var isCompletionNoticeHovered = false

    init(
        paths: CodexPaths = CodexPaths(),
        refreshInterval: TimeInterval = 2,
        executablePath: String = Bundle.main.executablePath ?? "/Applications/FloatMon.app/Contents/MacOS/FloatMon",
        integrations: [any AgentIntegration]? = nil
    ) {
        self.integrations = Self.integrationMap(
            integrations ?? [
                CodexAgentIntegration(paths: paths),
                OpenCodeAgentIntegration(paths: paths)
            ]
        )
        self.executablePath = executablePath
        refreshHookStatuses()
        snapshot = AgentSnapshot.empty(provider: selectedProvider, hookStatus: hookStatuses[selectedProvider] ?? .unknown)
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

        let provider = selectedProvider
        let status = hookStatuses[provider] ?? .unknown
        isRefreshing = true

        let integration = integrations[provider]
        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                integration?.readSnapshot(hookStatus: status)
                    ?? AgentSnapshot.empty(provider: provider, hookStatus: .failed("Agent provider is not configured"))
            }.value

            guard let self, !Task.isCancelled else { return }
            self.snapshotsByProvider[provider] = snapshot
            if self.selectedProvider == provider {
                self.snapshot = snapshot
                self.updateCompletionNotice(for: snapshot)
            }
            self.isRefreshing = false
        }
    }

    func setCompletionNoticeHovered(_ isHovered: Bool) {
        isCompletionNoticeHovered = isHovered
        if isHovered {
            clearCompletionNotice()
        }
    }

    func selectProvider(_ provider: AgentProvider) {
        guard selectedProvider != provider else { return }
        selectedProvider = provider
        snapshot = snapshotsByProvider[provider]
            ?? AgentSnapshot.empty(provider: provider, hookStatus: hookStatuses[provider] ?? .unknown)
        completionNotice = nil
        refresh(force: true)
    }

    func refreshHookStatus() {
        refreshHookStatuses()
        refresh(force: true)
    }

    func registerSelectedIntegration() {
        let provider = selectedProvider

        do {
            try integration(for: provider).register(executablePath: executablePath)
            hookStatuses[provider] = .registered
        } catch {
            hookStatuses[provider] = .failed(error.localizedDescription)
        }
        refresh()
    }

    func detachSelectedIntegration() {
        let provider = selectedProvider

        do {
            try integration(for: provider).detach()
            hookStatuses[provider] = .missing
        } catch {
            hookStatuses[provider] = .failed(error.localizedDescription)
        }
        refresh(force: true)
    }

    private func refreshHookStatuses() {
        for provider in AgentProvider.allCases {
            hookStatuses[provider] = integration(for: provider).isRegistered(executablePath: executablePath)
                ? .registered
                : .missing
        }
    }

    private func updateCompletionNotice(for snapshot: AgentSnapshot) {
        if let notice = completionNotifier.notice(for: snapshot) {
            if isCompletionNoticeHovered {
                clearCompletionNotice()
            } else {
                completionNotice = notice
            }
            return
        }

        if let completionNotice, completionNotifier.shouldDismiss(completionNotice, for: snapshot) {
            clearCompletionNotice()
        }
    }

    private func clearCompletionNotice() {
        completionNotice = nil
    }

    private func integration(for provider: AgentProvider) -> any AgentIntegration {
        integrations[provider] ?? MissingAgentIntegration(provider: provider)
    }

    private static func integrationMap(_ integrations: [any AgentIntegration]) -> [AgentProvider: any AgentIntegration] {
        Dictionary(uniqueKeysWithValues: integrations.map { ($0.provider, $0) })
    }
}

private struct MissingAgentIntegration: AgentIntegration {
    let provider: AgentProvider

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        AgentSnapshot.empty(provider: provider, hookStatus: .failed("Agent provider is not configured"))
    }

    func isRegistered(executablePath: String) -> Bool {
        false
    }

    func register(executablePath: String) throws {
        throw NSError(domain: "FloatMon.AgentStore", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Agent provider is not configured"
        ])
    }

    func detach() throws {
        throw NSError(domain: "FloatMon.AgentStore", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Agent provider is not configured"
        ])
    }
}
