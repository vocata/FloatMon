import SwiftUI

struct AgentMonitorView: View {
    let snapshot: AgentSnapshot
    let refresh: () -> Void

    private var recentEvents: [AgentEvent] {
        Array(snapshot.recentEvents.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            VStack(spacing: 4) {
                InfoRow(
                    title: "Thread",
                    value: snapshot.currentThread?.title ?? "No active thread",
                    systemImage: "text.bubble"
                )
                InfoRow(
                    title: "Workspace",
                    value: workspaceLabel,
                    systemImage: "folder"
                )
                InfoRow(
                    title: "Tokens",
                    value: tokensLabel,
                    systemImage: "number"
                )
                InfoRow(
                    title: "Goal",
                    value: goalLabel,
                    systemImage: "target"
                )
            }

            eventsSection
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(.white.opacity(0.09))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.provider.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(snapshot.hookStatus.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.08))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverTooltip("Refresh")
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recent Events")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)

            if recentEvents.isEmpty {
                Text("No hook events yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.055))
                    }
            } else {
                VStack(spacing: 4) {
                    ForEach(recentEvents) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }

    private var workspaceLabel: String {
        guard let cwd = snapshot.currentThread?.cwd, !cwd.isEmpty else {
            return snapshot.unavailableReason ?? "Unavailable"
        }

        return URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    private var tokensLabel: String {
        guard let thread = snapshot.currentThread else { return "0" }
        if let budget = snapshot.currentGoal?.tokenBudget {
            return "\(AppFormatters.integer(thread.tokensUsed)) / \(AppFormatters.integer(budget))"
        }
        return AppFormatters.integer(thread.tokensUsed)
    }

    private var goalLabel: String {
        guard let goal = snapshot.currentGoal else { return "No active goal" }
        return "\(goal.status): \(goal.objective)"
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 16)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        }
    }
}

private struct EventRow: View {
    let event: AgentEvent

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(event.status.statusColor)
                .frame(width: 7, height: 7)

            Text(event.type)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.045))
        }
    }

    private var detail: String {
        if let toolName = event.toolName, !toolName.isEmpty {
            return "\(toolName) · \(event.status.rawValue)"
        }
        return event.status.rawValue
    }
}

private extension AgentEvent.Status {
    var statusColor: Color {
        switch self {
        case .idle:
            return .gray
        case .running:
            return .green
        case .waiting:
            return .orange
        case .completed:
            return .cyan
        case .failed:
            return .red
        }
    }
}
