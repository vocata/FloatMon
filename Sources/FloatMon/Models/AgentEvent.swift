import Foundation

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
}
