import Foundation

struct AgentCompletionNotice: Equatable, Identifiable {
    let id: String
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

        return AgentCompletionNotice(id: event.id)
    }

    func shouldDismiss(_ notice: AgentCompletionNotice, for snapshot: AgentSnapshot) -> Bool {
        guard let latestEvent = snapshot.recentEvents.first else {
            return false
        }
        return latestEvent.id != notice.id
    }
}
