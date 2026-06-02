enum CollapsedAppSortMode {
    static func target(for swipeDirection: WindowSwipeDirection) -> ProcessSortMode {
        swipeDirection == .right ? .cpu : .memory
    }
}
