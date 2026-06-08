import Foundation

enum AgentActivitySignal: Equatable {
    case active
    case permission
    case output
    case completed
    case retrying
    case message
    case compacting
    case error
    case neutral
}

struct AgentEvent: Codable, Equatable, Identifiable {
    var id: String {
        "\(provider.rawValue)-\(type)-\(timestamp.timeIntervalSince1970)-\(threadID ?? "none")-\(toolName ?? "none")-\(detail ?? "none")-\(message ?? "none")"
    }

    let provider: AgentProvider
    let type: String
    let timestamp: Date
    let threadID: String?
    let toolName: String?
    let detail: String?
    let message: String?

    var isRich: Bool {
        if let detail, !detail.isEmpty { return true }
        if let message, !message.isEmpty { return true }
        return false
    }

    var displayBodyText: String? {
        Self.nonEmpty(message) ?? Self.nonEmpty(detail)
    }

    var displayToolLabel: String {
        Self.nonEmpty(toolName) ?? Self.nonEmpty(detail) ?? ""
    }

    var compactSummary: String {
        var parts = [type]
        if let toolName = Self.nonEmpty(toolName) {
            parts.append(toolName)
        }
        if let detail = Self.nonEmpty(detail), detail != toolName {
            parts.append(detail.singleLineSummary(maxLength: 360))
        }
        if let message = Self.nonEmpty(message), message != detail {
            parts.append(message.singleLineSummary(maxLength: 360))
        }
        return parts.joined(separator: " · ")
    }

    var activitySignal: AgentActivitySignal {
        if provider == .opencode, type == "session.status" {
            return openCodeSessionStatusSignal
        }

        switch type {
        case "tool.execute.before", "PreToolUse", "SubagentStart":
            return .active
        case "permission.asked", "PermissionRequest":
            return .permission
        case "tool.execute.after", "PostToolUse":
            return .output
        case "permission.replied", "session.compacted", "Stop", "PostCompact", "SubagentStop":
            return .completed
        case "message.updated", "message.part.updated", "UserPromptSubmit":
            return .message
        case "session.error":
            return .error
        case "PreCompact":
            return .compacting
        default:
            return .neutral
        }
    }

    private var openCodeSessionStatusSignal: AgentActivitySignal {
        guard let detail = Self.nonEmpty(detail) else {
            return .neutral
        }
        if detail == "idle" {
            return .completed
        }
        if detail == "busy" {
            return .active
        }
        if detail == "retry" {
            return .retrying
        }
        return .neutral
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case type
        case timestamp
        case threadID
        case toolName
        case detail
        case message
    }

    init(
        provider: AgentProvider,
        type: String,
        timestamp: Date,
        threadID: String?,
        toolName: String?,
        detail: String? = nil,
        message: String? = nil
    ) {
        self.provider = provider
        self.type = type
        self.timestamp = timestamp
        self.threadID = threadID
        self.toolName = toolName
        self.detail = detail
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AgentProvider.self, forKey: .provider)
        type = try container.decode(String.self, forKey: .type)
        let timestampSeconds = try container.decode(Double.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: timestampSeconds)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
        try container.encodeIfPresent(threadID, forKey: .threadID)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(message, forKey: .message)
    }

    static func decodeJSONLine(_ line: String) throws -> AgentEvent {
        let data = Data(line.utf8)
        do {
            return try JSONDecoder().decode(AgentEvent.self, from: data)
        } catch {
            let unescapedLine = line.replacingOccurrences(of: #"\""#, with: #"""#)
            guard unescapedLine != line else { throw error }
            return try JSONDecoder().decode(AgentEvent.self, from: Data(unescapedLine.utf8))
        }
    }

    static func decodeLossyJSONLine(_ line: String) -> AgentEvent? {
        try? decodeJSONLine(line)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private extension String {
    func singleLineSummary(maxLength: Int) -> String {
        let normalized = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > maxLength, maxLength > 1 else {
            return normalized
        }
        return String(normalized.prefix(maxLength - 1)) + "..."
    }
}
