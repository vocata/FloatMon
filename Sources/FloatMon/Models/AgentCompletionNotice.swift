import Foundation

struct AgentCompletionNotice: Equatable, Identifiable {
    let id: String
}

struct AgentCompletionNotifier {
    private var seenCompletionEventIDsByProvider: [AgentProvider: Set<String>] = [:]
    private var seededProviders: Set<AgentProvider> = []

    mutating func notice(for snapshot: AgentSnapshot) -> AgentCompletionNotice? {
        let provider = snapshot.provider
        let completionEvents = snapshot.recentEvents.filter {
            $0.provider == provider && Self.isCompletionEvent($0)
        }
        defer {
            var seenCompletionEventIDs = seenCompletionEventIDsByProvider[provider] ?? []
            seenCompletionEventIDs.formUnion(completionEvents.map(\.id))
            seenCompletionEventIDsByProvider[provider] = seenCompletionEventIDs
        }

        guard seededProviders.contains(provider) else {
            seededProviders.insert(provider)
            return nil
        }

        let seenCompletionEventIDs = seenCompletionEventIDsByProvider[provider] ?? []
        guard let event = completionEvents.first(where: { !seenCompletionEventIDs.contains($0.id) }) else {
            return nil
        }

        return AgentCompletionNotice(id: event.id)
    }

    func shouldDismiss(_ notice: AgentCompletionNotice, for snapshot: AgentSnapshot) -> Bool {
        guard let latestEvent = snapshot.recentEvents.first else {
            return false
        }
        return latestEvent.id != notice.id
    }

    private static func isCompletionEvent(_ event: AgentEvent) -> Bool {
        switch (event.provider, event.type) {
        case (.codex, "Stop"):
            return true
        case (.opencode, "session.status"):
            return event.detail == "idle"
        default:
            return false
        }
    }
}
