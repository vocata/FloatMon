enum CollapsedAgentProviderMode {
    static func target(current: AgentProvider, swipeDirection: WindowSwipeDirection) -> AgentProvider {
        let providers = AgentProvider.allCases
        guard let index = providers.firstIndex(of: current) else {
            return current
        }

        switch swipeDirection {
        case .left:
            return providers[min(index + 1, providers.count - 1)]
        case .right:
            return providers[max(index - 1, 0)]
        }
    }
}
