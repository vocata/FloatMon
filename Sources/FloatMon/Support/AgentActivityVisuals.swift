import SwiftUI

extension AgentActivitySignal {
    var color: Color {
        switch self {
        case .active:
            return Color(red: 0.20, green: 0.55, blue: 1.00)
        case .permission:
            return Color(red: 1.00, green: 0.58, blue: 0.08)
        case .output:
            return Color(red: 0.00, green: 0.78, blue: 0.82)
        case .completed:
            return Color(red: 0.25, green: 0.92, blue: 0.42)
        case .retrying:
            return Color(red: 1.00, green: 0.68, blue: 0.12)
        case .message:
            return Color(red: 0.68, green: 0.43, blue: 1.00)
        case .compacting:
            return Color(red: 0.45, green: 0.56, blue: 0.68)
        case .error:
            return Color(red: 1.00, green: 0.26, blue: 0.32)
        case .neutral:
            return Color(red: 0.56, green: 0.58, blue: 0.62)
        }
    }

    var tone: ExternalHoverTooltipTone {
        switch self {
        case .active:
            return .blue
        case .permission, .retrying:
            return .orange
        case .output:
            return .teal
        case .completed:
            return .green
        case .message:
            return .purple
        case .error:
            return .red
        case .compacting, .neutral:
            return .neutral
        }
    }
}
