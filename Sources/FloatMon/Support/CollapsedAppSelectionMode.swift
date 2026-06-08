import Foundation

enum CollapsedAppSelectionMode {
    static func target(currentID: pid_t?, sortedAppIDs: [pid_t], swipeDirection: WindowVerticalSwipeDirection) -> pid_t? {
        guard !sortedAppIDs.isEmpty else { return nil }

        let currentIndex = currentID
            .flatMap { sortedAppIDs.firstIndex(of: $0) }
            ?? 0

        switch swipeDirection {
        case .up:
            return sortedAppIDs[min(currentIndex + 1, sortedAppIDs.count - 1)]
        case .down:
            return sortedAppIDs[max(currentIndex - 1, 0)]
        }
    }
}
