import Foundation

struct AgentCompletionNotice: Equatable, Identifiable {
    let id: String
    let provider: AgentProvider
    let title: String
    let detail: String
    let timestamp: Date
}

struct AgentCompletionNotifier {
    private var seenStopEventIDs: Set<String> = []
    private var didSeedInitialStops = false

    mutating func notice(for snapshot: AgentSnapshot) -> AgentCompletionNotice? {
        let stopEvents = snapshot.recentEvents.filter { $0.type == "Stop" }
        defer {
            seenStopEventIDs.formUnion(stopEvents.map(\.id))
        }

        guard didSeedInitialStops else {
            didSeedInitialStops = true
            return nil
        }

        guard let event = stopEvents.first(where: { !seenStopEventIDs.contains($0.id) }) else {
            return nil
        }

        return AgentCompletionNotice(
            id: event.id,
            provider: event.provider,
            title: "\(event.provider.displayName) finished",
            detail: detail(for: event, snapshot: snapshot),
            timestamp: event.timestamp
        )
    }

    private func detail(for event: AgentEvent, snapshot: AgentSnapshot) -> String {
        if let message = event.message, !message.isEmpty {
            return message
        }
        if let thread = snapshot.currentThread, thread.id == event.threadID {
            return thread.title
        }
        return "Task completed"
    }
}
