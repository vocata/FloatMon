import Foundation

struct OpenCodeHookWriter {
    let paths: CodexPaths
    private let eventLogWriter: AgentEventLogWriter

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.eventLogWriter = AgentEventLogWriter(paths: paths, fileManager: fileManager)
    }

    func write(eventType: String, stdinData: Data) throws {
        guard Self.supportedEventTypes.contains(eventType) else { return }

        let metadata = Self.metadata(from: stdinData)
        let display = metadata.display(for: eventType)
        let event = AgentEvent(
            provider: .opencode,
            type: eventType,
            timestamp: Date(),
            threadID: metadata.sessionID,
            toolName: metadata.toolName,
            detail: display.detail,
            message: display.message
        )
        try eventLogWriter.append(event)
        try eventLogWriter.writeLatestState(for: event)
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard
            let flagIndex = arguments.firstIndex(of: "--floatmon-opencode-hook"),
            arguments.indices.contains(flagIndex + 1)
        else {
            return false
        }

        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            try OpenCodeHookWriter().write(eventType: arguments[flagIndex + 1], stdinData: data)
            exit(0)
        } catch {
            fputs("FloatMon OpenCode hook writer failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static let supportedEventTypes = [
        "session.created",
        "session.status",
        "tool.execute.before",
        "permission.asked",
        "tool.execute.after",
        "session.compacted",
        "session.error"
    ]

    private struct Metadata {
        let sessionID: String?
        let toolName: String?
        let toolDetail: String?
        let eventDetail: String?
        let payloadDetail: String?
        let statusType: String?
        let statusMessage: String?

        func display(for eventType: String) -> (detail: String?, message: String?) {
            switch eventType {
            case "session.status":
                return (statusType ?? eventDetail ?? payloadDetail, statusMessage)
            case "session.created":
                return (eventDetail ?? payloadDetail ?? "Session started", nil)
            case "tool.execute.before", "permission.asked", "tool.execute.after":
                return (toolDetail ?? eventDetail ?? payloadDetail, nil)
            case "session.compacted":
                return (eventDetail ?? "Compacted", nil)
            case "session.error":
                return (eventDetail ?? payloadDetail ?? "Error", nil)
            default:
                return (eventDetail ?? toolDetail ?? payloadDetail, nil)
            }
        }
    }

    private static func metadata(from data: Data) -> Metadata {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Metadata(
                sessionID: nil,
                toolName: nil,
                toolDetail: nil,
                eventDetail: nil,
                payloadDetail: nil,
                statusType: nil,
                statusMessage: nil
            )
        }

        let event = object["event"] as? [String: Any]
        let input = object["input"] as? [String: Any]
        let output = object["output"] as? [String: Any]
        let context = object["context"] as? [String: Any]
        let eventProperties = event?["properties"] as? [String: Any]
        let status = eventProperties?["status"] as? [String: Any]

        let sessionID = firstString(in: [
            eventProperties,
            object,
            input,
            output,
            context,
            event
        ], keys: ["sessionID", "sessionId", "session_id"])
            ?? firstString(in: [
                eventProperties,
                object,
                input,
                output,
                context,
                event
            ], keys: ["id"])
        let toolName = firstString(
            in: [eventProperties, input, output, object],
            keys: ["tool", "toolName", "tool_name", "name"]
        )
        let toolDetail = firstSummary(
            in: [eventProperties, input, output],
            keys: ["args", "command", "description", "result", "text", "content"],
            limit: 12_000,
            preserveWhitespace: true
        )
        let eventDetail = firstSummary(
            in: [eventProperties, event, object],
            keys: ["description", "error", "status", "title", "directory", "path", "summary", "reason", "message"],
            limit: 4_000,
            preserveWhitespace: false
        )
        let payloadDetail = jsonSummary(from: object, limit: 12_000)

        return Metadata(
            sessionID: sessionID,
            toolName: toolName,
            toolDetail: toolDetail,
            eventDetail: eventDetail,
            payloadDetail: payloadDetail,
            statusType: normalizedText(status?["type"], limit: 100, preserveWhitespace: false),
            statusMessage: normalizedText(status?["message"], limit: 2_000, preserveWhitespace: false)
        )
    }

    private static func firstString(in objects: [[String: Any]?], keys: [String]) -> String? {
        for object in objects {
            guard let object else { continue }
            for key in keys {
                if let string = normalizedText(object[key], limit: 400, preserveWhitespace: false) {
                    return string
                }
            }
        }
        return nil
    }

    private static func firstSummary(
        in objects: [[String: Any]?],
        keys: [String],
        limit: Int,
        preserveWhitespace: Bool
    ) -> String? {
        for object in objects {
            guard let object else { continue }
            for key in keys {
                if let summary = summary(from: object[key], limit: limit, preserveWhitespace: preserveWhitespace) {
                    return summary
                }
            }
        }
        return nil
    }

    private static func summary(from value: Any?, limit: Int, preserveWhitespace: Bool) -> String? {
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
