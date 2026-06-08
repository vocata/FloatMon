import Foundation

protocol AgentIntegration {
    var provider: AgentProvider { get }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot
    func isRegistered(executablePath: String) -> Bool
    func register(executablePath: String) throws
    func detach() throws
}

struct CodexAgentIntegration: AgentIntegration {
    let provider: AgentProvider = .codex
    private let reader: CodexSnapshotReader
    private let registrationService: CodexHookRegistrationService

    init(paths: CodexPaths = CodexPaths()) {
        self.reader = CodexSnapshotReader(paths: paths)
        self.registrationService = CodexHookRegistrationService(paths: paths)
    }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        reader.readSnapshot(hookStatus: hookStatus)
    }

    func isRegistered(executablePath: String) -> Bool {
        registrationService.isRegistered(executablePath: executablePath)
    }

    func register(executablePath: String) throws {
        _ = try registrationService.register(executablePath: executablePath)
    }

    func detach() throws {
        _ = try registrationService.detach()
    }
}

struct OpenCodeAgentIntegration: AgentIntegration {
    let provider: AgentProvider = .opencode
    private let reader: OpenCodeSnapshotReader
    private let registrationService: OpenCodePluginRegistrationService

    init(paths: CodexPaths = CodexPaths()) {
        self.reader = OpenCodeSnapshotReader(paths: paths)
        self.registrationService = OpenCodePluginRegistrationService(paths: paths)
    }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        reader.readSnapshot(hookStatus: hookStatus)
    }

    func isRegistered(executablePath: String) -> Bool {
        registrationService.isRegistered(executablePath: executablePath)
    }

    func register(executablePath: String) throws {
        _ = try registrationService.register(executablePath: executablePath)
    }

    func detach() throws {
        _ = try registrationService.detach()
    }
}
