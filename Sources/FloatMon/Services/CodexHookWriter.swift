import Foundation

struct CodexHookWriter {
    let paths: CodexPaths
    private let eventLogWriter: AgentEventLogWriter

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.eventLogWriter = AgentEventLogWriter(paths: paths, fileManager: fileManager)
    }

    func write(eventType: String, stdinData: Data) throws {
        let metadata = Self.metadata(from: stdinData)
        let event = AgentEvent(
            provider: .codex,
            type: eventType,
            timestamp: Date(),
            threadID: metadata.threadID,
            toolName: metadata.toolName,
            detail: metadata.detail(for: eventType),
            message: metadata.message
        )
        try eventLogWriter.append(event)
        try eventLogWriter.writeLatestState(for: event)
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard
            let flagIndex = arguments.firstIndex(of: "--floatmon-codex-hook"),
            arguments.indices.contains(flagIndex + 1)
        else {
            return false
        }

        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            try CodexHookWriter().write(eventType: arguments[flagIndex + 1], stdinData: data)
            exit(0)
        } catch {
            fputs("FloatMon hook writer failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private struct Metadata {
        let threadID: String?
        let toolName: String?
        let source: String?
        let prompt: String?
        let toolInputDetail: String?
        let toolResponseDetail: String?
        let compactDetail: String?
        let subagentName: String?
        let subagentTask: String?
        let message: String?
        let payloadDetail: String?

        func detail(for eventType: String) -> String? {
            switch eventType {
            case "SessionStart":
                return source.map { "source: \($0)" }
            case "UserPromptSubmit":
                return prompt.map { "prompt: \($0)" }
            case "PreToolUse", "PermissionRequest":
                return toolInputDetail
            case "PostToolUse":
                return postToolUseDetail
            case "PreCompact", "PostCompact":
                return compactDetail ?? payloadDetail
            case "SubagentStart", "SubagentStop":
                return subagentDetail ?? payloadDetail
            case "Stop":
                return message == nil ? nil : "Assistant response"
            default:
                return toolInputDetail ?? prompt ?? source ?? payloadDetail
            }
        }

        private var subagentDetail: String? {
            switch (subagentName, subagentTask) {
            case let (name?, task?):
                return "\(name): \(task)"
            case let (name?, nil):
                return name
            case let (nil, task?):
                return task
            case (nil, nil):
                return nil
            }
        }

        private var postToolUseDetail: String? {
            switch (toolInputDetail, toolResponseDetail) {
            case let (input?, response?):
                return "Input:\n\(input)\n\nOutput:\n\(response)"
            case let (input?, nil):
                return input
            case let (nil, response?):
                return response
            case (nil, nil):
                return nil
            }
        }
    }

    private static func metadata(from data: Data) -> Metadata {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Metadata(
                threadID: nil,
                toolName: nil,
                source: nil,
                prompt: nil,
                toolInputDetail: nil,
                toolResponseDetail: nil,
                compactDetail: nil,
                subagentName: nil,
                subagentTask: nil,
                message: nil,
                payloadDetail: nil
            )
        }

        let threadID = object["thread_id"] as? String
            ?? object["threadId"] as? String
            ?? object["threadID"] as? String
            ?? object["turn_id"] as? String
            ?? object["turnId"] as? String
            ?? object["session_id"] as? String
            ?? object["sessionId"] as? String
            ?? object["sessionID"] as? String
        let toolName = object["tool_name"] as? String
            ?? object["toolName"] as? String
            ?? object["tool"] as? String
        let source = object["source"] as? String
        let prompt = normalizedText(object["prompt"], limit: 2_000, preserveWhitespace: false)
        let toolInputDetail = summary(from: object["tool_input"] ?? object["toolInput"], limit: 12_000, preserveWhitespace: true)
        let toolResponseDetail = summary(from: object["tool_response"] ?? object["toolResponse"], limit: 12_000, preserveWhitespace: true)
        let compactDetail = firstSummary(
            in: object,
            keys: ["compact_summary", "compactSummary", "summary", "reason", "trigger"],
            limit: 4_000,
            preserveWhitespace: false
        )
        let subagentName = firstSummary(
            in: object,
            keys: ["subagent_name", "subagentName", "agent_name", "agentName", "name", "subagent_type", "subagentType"],
            limit: 200,
            preserveWhitespace: false
        )
        let subagentTask = firstSummary(
            in: object,
            keys: ["task", "description", "prompt", "message"],
            limit: 4_000,
            preserveWhitespace: false
        )
        let message = normalizedSummary(
            object["last_assistant_message"]
                ?? object["lastAssistantMessage"]
                ?? object["message"]
                ?? object["content"],
            limit: 2_000
        )
        let payloadDetail = jsonSummary(from: object, limit: 12_000)
        return Metadata(
            threadID: threadID,
            toolName: toolName,
            source: source,
            prompt: prompt,
            toolInputDetail: toolInputDetail,
            toolResponseDetail: toolResponseDetail,
            compactDetail: compactDetail,
            subagentName: subagentName,
            subagentTask: subagentTask,
            message: message,
            payloadDetail: payloadDetail
        )
    }

    private static func firstSummary(
        in object: [String: Any],
        keys: [String],
        limit: Int,
        preserveWhitespace: Bool
    ) -> String? {
        for key in keys {
            if let summary = summary(from: object[key], limit: limit, preserveWhitespace: preserveWhitespace) {
                return summary
            }
        }
        return nil
    }

    private static func summary(from value: Any?, limit: Int = 180, preserveWhitespace: Bool = false) -> String? {
        if let string = value as? String {
            return normalizedText(string, limit: limit, preserveWhitespace: preserveWhitespace)
        }

        if let object = value as? [String: Any] {
            if let command = normalizedText(object["command"], limit: limit, preserveWhitespace: preserveWhitespace) {
                return command
            }
            if let description = normalizedText(object["description"], limit: limit, preserveWhitespace: preserveWhitespace) {
                return description
            }
        }

        guard let value else { return nil }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return normalizedText(string, limit: limit, preserveWhitespace: preserveWhitespace)
    }

    private static func jsonSummary(from object: [String: Any], limit: Int) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return normalizedText(string, limit: limit, preserveWhitespace: true)
    }

    private static func normalizedSummary(_ value: Any?, limit: Int = 180) -> String? {
        normalizedText(value, limit: limit, preserveWhitespace: false)
    }

    private static func normalizedText(_ value: Any?, limit: Int, preserveWhitespace: Bool) -> String? {
        guard let string = value as? String else { return nil }
        let normalized: String
        if preserveWhitespace {
            normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalized = string
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !normalized.isEmpty else { return nil }
        guard normalized.count > limit else { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

}

extension JSONEncoder {
    static var floatMon: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
