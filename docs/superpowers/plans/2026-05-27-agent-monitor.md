# Agent Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a double-clickable agent monitoring mode to FloatMon, with an MVP Codex provider that can register backed-up Codex hooks and show current usage/task state.

**Architecture:** Keep app monitoring intact and add a parallel `AgentStore` that produces an `AgentSnapshot`. Codex live events are written by the FloatMon executable when invoked with a hook CLI flag; the app reads those event files plus Codex sqlite snapshots. Hook registration is explicit, startup-prompted, backed up, and idempotent.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, SwiftPM, XCTest, Foundation `Process` for sqlite queries, JSONSerialization/Codable for hook and event files.

---

## File Structure

- Modify `Package.swift`: add an XCTest target for logic tests.
- Modify `Sources/FloatMon/App/FloatMonApp.swift`: route `--floatmon-codex-hook <event>` invocations to the hook writer before launching UI.
- Modify `Sources/FloatMon/App/AppDelegate.swift`: create `AgentStore`, pass it into `IslandWindow`, and prompt for hook registration after startup when needed.
- Modify `Sources/FloatMon/App/IslandWindow.swift`: accept `AgentStore` and pass it into `IslandView`.
- Modify `Sources/FloatMon/Support/WindowDragBridge.swift`: distinguish single click, double click, and drag.
- Modify `Sources/FloatMon/Views/IslandView.swift`: add app/agent mode state, double-click mode toggle, and expanded app/agent switch.
- Create `Sources/FloatMon/Models/AgentProvider.swift`: provider enum, MVP `.codex`.
- Create `Sources/FloatMon/Models/AgentMonitorMode.swift`: app vs agent mode.
- Create `Sources/FloatMon/Models/AgentEvent.swift`: normalized hook event.
- Create `Sources/FloatMon/Models/AgentSnapshot.swift`: current agent status, usage, goal, events, hook registration state.
- Create `Sources/FloatMon/Services/CodexPaths.swift`: testable path bundle for Codex files.
- Create `Sources/FloatMon/Services/CodexHookRegistrationService.swift`: check, backup, and merge `hooks.json`.
- Create `Sources/FloatMon/Services/CodexHookWriter.swift`: CLI hook entry point.
- Create `Sources/FloatMon/Services/CodexSnapshotReader.swift`: event file and sqlite snapshot reader.
- Create `Sources/FloatMon/Stores/AgentStore.swift`: main-actor refresh timer and registration facade.
- Create `Sources/FloatMon/Views/AgentMonitorView.swift`: expanded Codex monitor UI.
- Create tests under `Tests/FloatMonTests/`.

---

### Task 1: Add Test Target And Agent Models

**Files:**
- Modify: `Package.swift`
- Create: `Sources/FloatMon/Models/AgentProvider.swift`
- Create: `Sources/FloatMon/Models/AgentMonitorMode.swift`
- Create: `Sources/FloatMon/Models/AgentEvent.swift`
- Create: `Sources/FloatMon/Models/AgentSnapshot.swift`
- Create: `Tests/FloatMonTests/AgentEventTests.swift`

- [ ] **Step 1: Write failing event decoding tests**

Create `Tests/FloatMonTests/AgentEventTests.swift`:

```swift
import XCTest
@testable import FloatMon

final class AgentEventTests: XCTestCase {
    func testDecodesValidEventLine() throws {
        let line = #"{"provider":"codex","type":"PreToolUse","timestamp":1779868647.25,"threadID":"thread-1","toolName":"exec_command","status":"running"}"#

        let event = try AgentEvent.decodeJSONLine(line)

        XCTAssertEqual(event.provider, .codex)
        XCTAssertEqual(event.type, "PreToolUse")
        XCTAssertEqual(event.threadID, "thread-1")
        XCTAssertEqual(event.toolName, "exec_command")
        XCTAssertEqual(event.status, .running)
    }

    func testReturnsNilForMalformedEventLine() {
        XCTAssertNil(AgentEvent.decodeLossyJSONLine("{not-json"))
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

Run: `make build && swift test --filter AgentEventTests`

Expected: build or test compilation fails because `AgentEvent` and the test target do not exist.

- [ ] **Step 3: Add test target and minimal models**

Update `Package.swift` targets:

```swift
targets: [
    .executableTarget(
        name: "FloatMon",
        path: "Sources/FloatMon"
    ),
    .testTarget(
        name: "FloatMonTests",
        dependencies: ["FloatMon"],
        path: "Tests/FloatMonTests"
    )
]
```

Create `Sources/FloatMon/Models/AgentProvider.swift`:

```swift
import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        }
    }
}
```

Create `Sources/FloatMon/Models/AgentMonitorMode.swift`:

```swift
import Foundation

enum AgentMonitorMode: String, CaseIterable, Identifiable {
    case apps
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps:
            return "Apps"
        case .agent:
            return "Agent"
        }
    }
}
```

Create `Sources/FloatMon/Models/AgentEvent.swift`:

```swift
import Foundation

struct AgentEvent: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case idle
        case running
        case waiting
        case completed
        case failed
    }

    var id: String {
        "\(provider.rawValue)-\(type)-\(timestamp.timeIntervalSince1970)-\(threadID ?? "none")-\(toolName ?? "none")"
    }

    let provider: AgentProvider
    let type: String
    let timestamp: Date
    let threadID: String?
    let toolName: String?
    let status: Status

    private enum CodingKeys: String, CodingKey {
        case provider
        case type
        case timestamp
        case threadID
        case toolName
        case status
    }

    init(
        provider: AgentProvider,
        type: String,
        timestamp: Date,
        threadID: String?,
        toolName: String?,
        status: Status
    ) {
        self.provider = provider
        self.type = type
        self.timestamp = timestamp
        self.threadID = threadID
        self.toolName = toolName
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AgentProvider.self, forKey: .provider)
        type = try container.decode(String.self, forKey: .type)
        let timestampSeconds = try container.decode(Double.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: timestampSeconds)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        status = try container.decode(Status.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
        try container.encodeIfPresent(threadID, forKey: .threadID)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encode(status, forKey: .status)
    }

    static func decodeJSONLine(_ line: String) throws -> AgentEvent {
        let data = Data(line.utf8)
        return try JSONDecoder().decode(AgentEvent.self, from: data)
    }

    static func decodeLossyJSONLine(_ line: String) -> AgentEvent? {
        try? decodeJSONLine(line)
    }
}
```

Create `Sources/FloatMon/Models/AgentSnapshot.swift`:

```swift
import Foundation

struct AgentThreadSummary: Equatable {
    let id: String
    let title: String
    let cwd: String
    let tokensUsed: Int
    let updatedAt: Date
}

struct AgentGoalSummary: Equatable {
    let objective: String
    let status: String
    let tokenBudget: Int?
    let tokensUsed: Int
    let timeUsedSeconds: Int

    var budgetProgress: Double? {
        guard let tokenBudget, tokenBudget > 0 else { return nil }
        return min(max(Double(tokensUsed) / Double(tokenBudget), 0), 1)
    }
}

enum AgentHookStatus: Equatable {
    case unknown
    case missing
    case registered
    case declined
    case failed(String)

    var label: String {
        switch self {
        case .unknown:
            return "Checking hooks"
        case .missing:
            return "Hook not registered"
        case .registered:
            return "Hook active"
        case .declined:
            return "Hook skipped"
        case .failed:
            return "Hook error"
        }
    }
}

struct AgentSnapshot: Equatable {
    static let empty = AgentSnapshot(
        provider: .codex,
        activityStatus: .idle,
        hookStatus: .unknown,
        currentThread: nil,
        currentGoal: nil,
        recentEvents: [],
        lastUpdated: nil,
        unavailableReason: nil
    )

    let provider: AgentProvider
    let activityStatus: AgentEvent.Status
    let hookStatus: AgentHookStatus
    let currentThread: AgentThreadSummary?
    let currentGoal: AgentGoalSummary?
    let recentEvents: [AgentEvent]
    let lastUpdated: Date?
    let unavailableReason: String?
}
```

- [ ] **Step 4: Run tests and verify pass**

Run: `swift test --filter AgentEventTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/FloatMon/Models/AgentProvider.swift Sources/FloatMon/Models/AgentMonitorMode.swift Sources/FloatMon/Models/AgentEvent.swift Sources/FloatMon/Models/AgentSnapshot.swift Tests/FloatMonTests/AgentEventTests.swift
git commit -m "test: add agent monitor models"
```

---

### Task 2: Implement Codex Hook Registration

**Files:**
- Create: `Sources/FloatMon/Services/CodexPaths.swift`
- Create: `Sources/FloatMon/Services/CodexHookRegistrationService.swift`
- Create: `Tests/FloatMonTests/CodexHookRegistrationServiceTests.swift`

- [ ] **Step 1: Write failing registration tests**

Create `Tests/FloatMonTests/CodexHookRegistrationServiceTests.swift`:

```swift
import XCTest
@testable import FloatMon

final class CodexHookRegistrationServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonHookTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testRegisterCreatesBackupAndPreservesExistingHook() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try """
        {
          "hooks": {
            "PostToolUse": [
              {
                "hooks": [
                  {
                    "command": "echo existing",
                    "type": "command",
                    "timeout": 5
                  }
                ]
              }
            ]
          }
        }
        """.write(to: hooksURL, atomically: true, encoding: .utf8)
        let service = CodexHookRegistrationService(paths: CodexPaths(codexHome: root))

        let result = try service.register(executablePath: "/Applications/FloatMon.app/Contents/MacOS/FloatMon")

        XCTAssertTrue(result.backupURL.lastPathComponent.hasPrefix("hooks.floatmon-backup."))
        let output = try String(contentsOf: hooksURL, encoding: .utf8)
        XCTAssertTrue(output.contains("echo existing"))
        XCTAssertTrue(output.contains("--floatmon-codex-hook PostToolUse"))
    }

    func testRegisterIsIdempotent() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try #"{"hooks":{}}"#.write(to: hooksURL, atomically: true, encoding: .utf8)
        let service = CodexHookRegistrationService(paths: CodexPaths(codexHome: root))

        _ = try service.register(executablePath: "/tmp/FloatMon")
        _ = try service.register(executablePath: "/tmp/FloatMon")

        let output = try String(contentsOf: hooksURL, encoding: .utf8)
        let occurrences = output.components(separatedBy: "--floatmon-codex-hook SessionStart").count - 1
        XCTAssertEqual(occurrences, 1)
    }
}
```

- [ ] **Step 2: Run tests and verify fail**

Run: `swift test --filter CodexHookRegistrationServiceTests`

Expected: FAIL because `CodexPaths` and `CodexHookRegistrationService` do not exist.

- [ ] **Step 3: Implement path and registration service**

Create `Sources/FloatMon/Services/CodexPaths.swift`:

```swift
import Foundation

struct CodexPaths {
    let codexHome: URL

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.codexHome = codexHome
    }

    var hooksJSON: URL {
        codexHome.appendingPathComponent("hooks.json")
    }

    var floatMonDirectory: URL {
        codexHome.appendingPathComponent("floatmon", isDirectory: true)
    }

    var eventsJSONL: URL {
        floatMonDirectory.appendingPathComponent("events.jsonl")
    }

    var stateJSON: URL {
        floatMonDirectory.appendingPathComponent("state.json")
    }

    var stateSQLite: URL {
        codexHome.appendingPathComponent("state_5.sqlite")
    }

    var goalsSQLite: URL {
        codexHome.appendingPathComponent("goals_1.sqlite")
    }

    func backupHooksURL(now: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        return codexHome.appendingPathComponent("hooks.floatmon-backup.\(stamp).json")
    }
}
```

Create `Sources/FloatMon/Services/CodexHookRegistrationService.swift`:

```swift
import Foundation

struct CodexHookRegistrationResult: Equatable {
    let backupURL: URL
}

struct CodexHookRegistrationService {
    private static let events = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop"
    ]

    let paths: CodexPaths
    private let fileManager: FileManager

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func isRegistered(executablePath: String) -> Bool {
        guard
            let root = try? loadRoot(),
            let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }

        return Self.events.allSatisfy { event in
            eventHookCommands(for: event, in: hooks)
                .contains { $0.contains("--floatmon-codex-hook \(event)") && $0.contains(executablePath) }
        }
    }

    func register(executablePath: String) throws -> CodexHookRegistrationResult {
        try fileManager.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: paths.hooksJSON.path) {
            try #"{"hooks":{}}"#.write(to: paths.hooksJSON, atomically: true, encoding: .utf8)
        }

        let backupURL = paths.backupHooksURL()
        try fileManager.copyItem(at: paths.hooksJSON, to: backupURL)

        var root = try loadRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            mergeHook(event: event, executablePath: executablePath, into: &hooks)
        }
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: paths.hooksJSON, options: .atomic)
        return CodexHookRegistrationResult(backupURL: backupURL)
    }

    private func loadRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: paths.hooksJSON)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? ["hooks": [String: Any]()]
    }

    private func eventHookCommands(for event: String, in hooks: [String: Any]) -> [String] {
        guard let entries = hooks[event] as? [[String: Any]] else { return [] }
        return entries.flatMap { entry -> [String] in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return [] }
            return hookList.compactMap { $0["command"] as? String }
        }
    }

    private func mergeHook(event: String, executablePath: String, into hooks: inout [String: Any]) {
        let command = Self.command(executablePath: executablePath, event: event)
        var entries = hooks[event] as? [[String: Any]] ?? []
        let alreadyRegistered = entries.contains { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
            return hookList.contains { ($0["command"] as? String) == command }
        }

        guard !alreadyRegistered else {
            hooks[event] = entries
            return
        }

        entries.append([
            "hooks": [
                [
                    "command": command,
                    "type": "command",
                    "timeout": event == "PermissionRequest" ? 86400 : 5
                ]
            ]
        ])
        hooks[event] = entries
    }

    static func command(executablePath: String, event: String) -> String {
        let escapedPath = executablePath.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escapedPath)' --floatmon-codex-hook \(event)"
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run: `swift test --filter CodexHookRegistrationServiceTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatMon/Services/CodexPaths.swift Sources/FloatMon/Services/CodexHookRegistrationService.swift Tests/FloatMonTests/CodexHookRegistrationServiceTests.swift
git commit -m "feat: add codex hook registration"
```

---

### Task 3: Implement Codex Hook Writer

**Files:**
- Modify: `Sources/FloatMon/App/FloatMonApp.swift`
- Create: `Sources/FloatMon/Services/CodexHookWriter.swift`
- Create: `Tests/FloatMonTests/CodexHookWriterTests.swift`

- [ ] **Step 1: Write failing hook writer tests**

Create `Tests/FloatMonTests/CodexHookWriterTests.swift`:

```swift
import XCTest
@testable import FloatMon

final class CodexHookWriterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testWritesEventLineAndLatestState() throws {
        let writer = CodexHookWriter(paths: CodexPaths(codexHome: root))
        let payload = #"{"thread_id":"thread-1","tool_name":"exec_command"}"#.data(using: .utf8)!

        try writer.write(eventType: "PreToolUse", stdinData: payload)

        let events = try String(contentsOf: root.appendingPathComponent("floatmon/events.jsonl"), encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"PreToolUse""#))
        XCTAssertTrue(events.contains(#""threadID":"thread-1""#))
        XCTAssertTrue(events.contains(#""toolName":"exec_command""#))

        let state = try String(contentsOf: root.appendingPathComponent("floatmon/state.json"), encoding: .utf8)
        XCTAssertTrue(state.contains(#""activityStatus":"running""#))
    }
}
```

- [ ] **Step 2: Run test and verify fail**

Run: `swift test --filter CodexHookWriterTests`

Expected: FAIL because `CodexHookWriter` does not exist.

- [ ] **Step 3: Implement hook writer and CLI route**

Create `Sources/FloatMon/Services/CodexHookWriter.swift`:

```swift
import Foundation

struct CodexHookWriter {
    struct LatestState: Codable {
        let provider: AgentProvider
        let activityStatus: AgentEvent.Status
        let lastEvent: AgentEvent
    }

    let paths: CodexPaths
    private let fileManager: FileManager

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func write(eventType: String, stdinData: Data) throws {
        try fileManager.createDirectory(at: paths.floatMonDirectory, withIntermediateDirectories: true)
        let metadata = Self.metadata(from: stdinData)
        let event = AgentEvent(
            provider: .codex,
            type: eventType,
            timestamp: Date(),
            threadID: metadata.threadID,
            toolName: metadata.toolName,
            status: Self.status(for: eventType)
        )
        try append(event)
        try writeLatestState(for: event)
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

    private func append(_ event: AgentEvent) throws {
        let data = try JSONEncoder.floatMon.encode(event)
        var line = data
        line.append(UInt8(ascii: "\n"))

        if fileManager.fileExists(atPath: paths.eventsJSONL.path) {
            let handle = try FileHandle(forWritingTo: paths.eventsJSONL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: paths.eventsJSONL, options: .atomic)
        }
    }

    private func writeLatestState(for event: AgentEvent) throws {
        let state = LatestState(provider: .codex, activityStatus: event.status, lastEvent: event)
        let data = try JSONEncoder.floatMon.encode(state)
        try data.write(to: paths.stateJSON, options: .atomic)
    }

    private struct Metadata {
        let threadID: String?
        let toolName: String?
    }

    private static func metadata(from data: Data) -> Metadata {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Metadata(threadID: nil, toolName: nil)
        }

        let threadID = object["thread_id"] as? String
            ?? object["threadId"] as? String
            ?? object["threadID"] as? String
        let toolName = object["tool_name"] as? String
            ?? object["toolName"] as? String
            ?? object["tool"] as? String
        return Metadata(threadID: threadID, toolName: toolName)
    }

    private static func status(for eventType: String) -> AgentEvent.Status {
        switch eventType {
        case "PreToolUse":
            return .running
        case "PermissionRequest":
            return .waiting
        case "PostToolUse", "Stop":
            return .completed
        default:
            return .idle
        }
    }
}

private extension JSONEncoder {
    static var floatMon: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
```

Modify `Sources/FloatMon/App/FloatMonApp.swift`:

```swift
import SwiftUI

@main
struct FloatMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = CodexHookWriter.runIfRequested()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run: `swift test --filter CodexHookWriterTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatMon/App/FloatMonApp.swift Sources/FloatMon/Services/CodexHookWriter.swift Tests/FloatMonTests/CodexHookWriterTests.swift
git commit -m "feat: write codex hook events"
```

---

### Task 4: Implement Codex Snapshot Reader And Agent Store

**Files:**
- Create: `Sources/FloatMon/Services/CodexSnapshotReader.swift`
- Create: `Sources/FloatMon/Stores/AgentStore.swift`
- Create: `Tests/FloatMonTests/CodexSnapshotReaderTests.swift`

- [ ] **Step 1: Write failing event reader test**

Create `Tests/FloatMonTests/CodexSnapshotReaderTests.swift`:

```swift
import XCTest
@testable import FloatMon

final class CodexSnapshotReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("floatmon", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testReadsRecentEventsAndIgnoresMalformedLines() throws {
        let eventsURL = root.appendingPathComponent("floatmon/events.jsonl")
        try """
        {"provider":"codex","type":"PreToolUse","timestamp":1779868647.25,"threadID":"thread-1","toolName":"exec_command","status":"running"}
        not-json
        {"provider":"codex","type":"Stop","timestamp":1779868650.25,"threadID":"thread-1","status":"completed"}
        """.write(to: eventsURL, atomically: true, encoding: .utf8)
        let reader = CodexSnapshotReader(paths: CodexPaths(codexHome: root))

        let events = reader.readRecentEvents(limit: 5)

        XCTAssertEqual(events.map(\.type), ["Stop", "PreToolUse"])
    }

    func testMissingSqliteFilesReturnUnavailableSnapshot() {
        let reader = CodexSnapshotReader(paths: CodexPaths(codexHome: root))

        let snapshot = reader.readSnapshot(hookStatus: .missing)

        XCTAssertEqual(snapshot.hookStatus, .missing)
        XCTAssertNotNil(snapshot.unavailableReason)
    }
}
```

- [ ] **Step 2: Run tests and verify fail**

Run: `swift test --filter CodexSnapshotReaderTests`

Expected: FAIL because `CodexSnapshotReader` does not exist.

- [ ] **Step 3: Implement reader and store**

Create `Sources/FloatMon/Services/CodexSnapshotReader.swift`:

```swift
import Foundation

struct CodexSnapshotReader {
    let paths: CodexPaths

    init(paths: CodexPaths = CodexPaths()) {
        self.paths = paths
    }

    func readSnapshot(hookStatus: AgentHookStatus) -> AgentSnapshot {
        let events = readRecentEvents(limit: 8)
        let thread = readCurrentThread()
        let goal = thread.flatMap { readGoal(threadID: $0.id) }
        let status = events.first?.status ?? .idle
        let sqliteAvailable = FileManager.default.fileExists(atPath: paths.stateSQLite.path)

        return AgentSnapshot(
            provider: .codex,
            activityStatus: status,
            hookStatus: hookStatus,
            currentThread: thread,
            currentGoal: goal,
            recentEvents: events,
            lastUpdated: Date(),
            unavailableReason: sqliteAvailable ? nil : "Codex sqlite state is unavailable"
        )
    }

    func readRecentEvents(limit: Int) -> [AgentEvent] {
        guard
            let content = try? String(contentsOf: paths.eventsJSONL, encoding: .utf8)
        else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { AgentEvent.decodeLossyJSONLine(String($0)) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    private func readCurrentThread() -> AgentThreadSummary? {
        guard FileManager.default.fileExists(atPath: paths.stateSQLite.path) else { return nil }
        let query = "select id,title,cwd,tokens_used,updated_at_ms from threads order by updated_at_ms desc limit 1;"
        guard let line = runSQLite(path: paths.stateSQLite.path, query: query)?.first else { return nil }
        let fields = line.components(separatedBy: "|")
        guard fields.count >= 5 else { return nil }

        return AgentThreadSummary(
            id: fields[0],
            title: fields[1].isEmpty ? "Untitled Codex thread" : fields[1],
            cwd: fields[2],
            tokensUsed: Int(fields[3]) ?? 0,
            updatedAt: Date(timeIntervalSince1970: (Double(fields[4]) ?? 0) / 1000)
        )
    }

    private func readGoal(threadID: String) -> AgentGoalSummary? {
        guard FileManager.default.fileExists(atPath: paths.goalsSQLite.path) else { return nil }
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let query = "select objective,status,coalesce(token_budget,''),tokens_used,time_used_seconds from thread_goals where thread_id='\(escapedThreadID)' limit 1;"
        guard let line = runSQLite(path: paths.goalsSQLite.path, query: query)?.first else { return nil }
        let fields = line.components(separatedBy: "|")
        guard fields.count >= 5 else { return nil }

        return AgentGoalSummary(
            objective: fields[0],
            status: fields[1],
            tokenBudget: fields[2].isEmpty ? nil : Int(fields[2]),
            tokensUsed: Int(fields[3]) ?? 0,
            timeUsedSeconds: Int(fields[4]) ?? 0
        )
    }

    private func runSQLite(path: String, query: String) -> [String]? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(separator: "\n")
            .map(String.init)
    }
}
```

Create `Sources/FloatMon/Stores/AgentStore.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AgentStore {
    var snapshot = AgentSnapshot.empty
    var shouldPromptForCodexHook = false

    private let paths: CodexPaths
    private let reader: CodexSnapshotReader
    private let registrationService: CodexHookRegistrationService
    private let executablePath: String
    private var hookStatus: AgentHookStatus = .unknown
    private var timer: Timer?

    init(
        paths: CodexPaths = CodexPaths(),
        refreshInterval: TimeInterval = 2,
        executablePath: String = Bundle.main.executablePath ?? "/Applications/FloatMon.app/Contents/MacOS/FloatMon"
    ) {
        self.paths = paths
        self.reader = CodexSnapshotReader(paths: paths)
        self.registrationService = CodexHookRegistrationService(paths: paths)
        self.executablePath = executablePath
        refreshHookStatus()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        snapshot = reader.readSnapshot(hookStatus: hookStatus)
    }

    func refreshHookStatus() {
        if registrationService.isRegistered(executablePath: executablePath) {
            hookStatus = .registered
            shouldPromptForCodexHook = false
        } else {
            hookStatus = .missing
            shouldPromptForCodexHook = true
        }
    }

    func declineHookRegistration() {
        hookStatus = .declined
        shouldPromptForCodexHook = false
        refresh()
    }

    func registerCodexHook() {
        do {
            _ = try registrationService.register(executablePath: executablePath)
            hookStatus = .registered
            shouldPromptForCodexHook = false
        } catch {
            hookStatus = .failed(error.localizedDescription)
            shouldPromptForCodexHook = false
        }
        refresh()
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run: `swift test --filter CodexSnapshotReaderTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatMon/Services/CodexSnapshotReader.swift Sources/FloatMon/Stores/AgentStore.swift Tests/FloatMonTests/CodexSnapshotReaderTests.swift
git commit -m "feat: read codex agent snapshots"
```

---

### Task 5: Add Startup Hook Prompt Wiring

**Files:**
- Modify: `Sources/FloatMon/App/AppDelegate.swift`
- Modify: `Sources/FloatMon/App/IslandWindow.swift`

- [ ] **Step 1: Write a compile-focused expectation**

No separate unit test is needed because this task wires AppKit UI. The expected compile failure before implementation is that `IslandWindow` does not accept `AgentStore`.

Run: `swift test`

Expected before implementation: compiler errors after Task 4 if `AppDelegate` tries to pass `AgentStore` before `IslandWindow` is updated.

- [ ] **Step 2: Wire AgentStore and startup prompt**

Modify `Sources/FloatMon/App/AppDelegate.swift` to include `agentStore`, stop it on termination, create it in `showIsland`, and prompt after the island is shown:

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindow: IslandWindow?
    private var permissionWindow: NSWindow?
    private var processStore: ProcessStore?
    private var agentStore: AgentStore?
    private var didShowHookPrompt = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        continueWhenAuthorized()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        processStore?.stop()
        agentStore?.stop()
    }

    private func continueWhenAuthorized() {
        if AccessibilityPermissionService.isTrusted(prompt: false) {
            showIsland()
        } else {
            showPermissionWindow()
        }
    }

    // Keep the existing showPermissionWindow implementation unchanged.

    private func showIsland() {
        permissionWindow?.close()
        permissionWindow = nil

        if let islandWindow {
            islandWindow.orderFrontRegardless()
            maybePromptForCodexHook()
            return
        }

        let processStore = ProcessStore()
        let agentStore = AgentStore()
        self.processStore = processStore
        self.agentStore = agentStore
        let window = IslandWindow(processStore: processStore, agentStore: agentStore)
        islandWindow = window
        window.show()
        maybePromptForCodexHook()
    }

    private func maybePromptForCodexHook() {
        guard
            !didShowHookPrompt,
            let agentStore,
            agentStore.shouldPromptForCodexHook
        else {
            return
        }

        didShowHookPrompt = true
        let alert = NSAlert()
        alert.messageText = "Register Codex monitoring hook?"
        alert.informativeText = "FloatMon can monitor Codex live events by adding its hook command to ~/.codex/hooks.json. The current hooks file will be backed up before any change."
        alert.addButton(withTitle: "Register")
        alert.addButton(withTitle: "Skip")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            agentStore.registerCodexHook()
        } else {
            agentStore.declineHookRegistration()
        }
    }
}
```

Modify `Sources/FloatMon/App/IslandWindow.swift` initializer and hosting view setup:

```swift
private let processStore: ProcessStore
private let agentStore: AgentStore

init(processStore: ProcessStore, agentStore: AgentStore) {
    self.processStore = processStore
    self.agentStore = agentStore
    ...
    let hostingView = ClearHostingView(
        rootView: IslandView(
            store: processStore,
            agentStore: agentStore,
            resizeWindow: { [weak self] expanded in
                self?.resize(expanded: expanded)
            }
        )
    )
    ...
}
```

- [ ] **Step 3: Run compile check**

Run: `swift test`

Expected: PASS or only UI errors that are fixed in the next task if `IslandView` signature has not been updated yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/FloatMon/App/AppDelegate.swift Sources/FloatMon/App/IslandWindow.swift
git commit -m "feat: prompt for codex hook registration"
```

---

### Task 6: Add Double-Click Mode Switching And Agent UI

**Files:**
- Modify: `Sources/FloatMon/Support/WindowDragBridge.swift`
- Modify: `Sources/FloatMon/Views/IslandView.swift`
- Create: `Sources/FloatMon/Views/AgentMonitorView.swift`

- [ ] **Step 1: Write compile-focused UI expectation**

Run: `swift test`

Expected before implementation: compiler error because `IslandView` does not yet accept `agentStore`.

- [ ] **Step 2: Add double-click callback to drag bridge**

Modify `WindowDragBridge`:

```swift
struct WindowDragBridge: NSViewRepresentable {
    let onClick: () -> Void
    var onDoubleClick: () -> Void = {}
    var onPressChanged: (Bool) -> Void = { _ in }

    func updateNSView(_ nsView: DragView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.onPressChanged = onPressChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick, onDoubleClick: onDoubleClick, onPressChanged: onPressChanged)
    }

    final class Coordinator {
        var onClick: () -> Void
        var onDoubleClick: () -> Void
        var onPressChanged: (Bool) -> Void

        init(onClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void, onPressChanged: @escaping (Bool) -> Void) {
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
            self.onPressChanged = onPressChanged
        }
    }
}
```

Modify `DragView.mouseUp` click handling:

```swift
if shouldClick {
    if event.clickCount >= 2 {
        coordinator.onDoubleClick()
    } else {
        coordinator.onClick()
    }
    releasePressAfterClick()
} else {
    setPressed(false)
}
```

- [ ] **Step 3: Add AgentMonitorView**

Create `Sources/FloatMon/Views/AgentMonitorView.swift`:

```swift
import SwiftUI

struct AgentMonitorView: View {
    let snapshot: AgentSnapshot
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusGrid
            recentEvents
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(snapshot.hookStatus.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer()

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .hoverTooltip("Refresh")
        }
    }

    private var statusGrid: some View {
        VStack(spacing: 8) {
            metricRow(title: "Thread", value: snapshot.currentThread?.title ?? "No recent Codex thread")
            metricRow(title: "Workspace", value: snapshot.currentThread?.cwd ?? snapshot.unavailableReason ?? "Unknown")
            metricRow(title: "Tokens", value: snapshot.currentThread.map { AppFormatters.integer($0.tokensUsed) } ?? "-")
            metricRow(title: "Goal", value: snapshot.currentGoal.map { "\($0.status): \($0.objective)" } ?? "No active goal")
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Events")
                .font(.system(size: 13, weight: .semibold))

            if snapshot.recentEvents.isEmpty {
                Text("No hook events yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(snapshot.recentEvents.prefix(5)) { event in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: event.status))
                            .frame(width: 7, height: 7)
                        Text(event.type)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(event.toolName ?? event.status.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                    }
                    .frame(height: 22)
                }
            }
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func color(for status: AgentEvent.Status) -> Color {
        switch status {
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
```

- [ ] **Step 4: Add integer formatter**

Modify `Sources/FloatMon/Support/Formatters.swift` with:

```swift
static func integer(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}
```

- [ ] **Step 5: Update IslandView for modes**

Modify `IslandView` initializer and state:

```swift
private let resizeWindow: (Bool) -> Void

@State private var store: ProcessStore
@State private var agentStore: AgentStore
@State private var expanded = false
@State private var monitorMode: AgentMonitorMode = .apps
```

Initializer:

```swift
init(store: ProcessStore, agentStore: AgentStore, resizeWindow: @escaping (Bool) -> Void) {
    _store = State(initialValue: store)
    _agentStore = State(initialValue: agentStore)
    self.resizeWindow = resizeWindow
}
```

Replace expanded content after the divider:

```swift
if expanded {
    modeSwitcher
        .padding(.horizontal, 18)
        .padding(.top, 12)

    if monitorMode == .apps {
        ExpandedProcessList(
            apps: store.apps,
            sortMode: $sortMode,
            activate: activateApp,
            focusWindow: focusWindow,
            closeWindow: closeWindow,
            requestForceQuit: { pendingForceQuitApp = $0 }
        )
        .transition(.opacity)
    } else {
        AgentMonitorView(
            snapshot: agentStore.snapshot,
            refresh: { agentStore.refresh() }
        )
        .transition(.opacity)
    }
}
```

Add mode switcher:

```swift
private var modeSwitcher: some View {
    HStack(spacing: 6) {
        ForEach(AgentMonitorMode.allCases) { mode in
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    monitorMode = mode
                }
            } label: {
                Text(mode.title)
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .foregroundStyle(monitorMode == mode ? .black.opacity(0.86) : .white.opacity(0.62))
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(monitorMode == mode ? .white.opacity(0.86) : .white.opacity(0.07))
                    }
            }
            .buttonStyle(.plain)
        }
    }
}
```

Update `WindowDragBridge` overlay call:

```swift
WindowDragBridge(
    onClick: toggleExpanded,
    onDoubleClick: toggleMonitorMode,
    onPressChanged: { togglePressed = $0 }
)
```

Add mode toggle:

```swift
private func toggleMonitorMode() {
    withAnimation(.easeInOut(duration: 0.18)) {
        monitorMode = monitorMode == .apps ? .agent : .apps
    }
}
```

In `collapsedHeader`, render agent mode when selected:

```swift
if monitorMode == .agent {
    agentCollapsedHeader
} else {
    appCollapsedHeader
}
```

Add `agentCollapsedHeader`:

```swift
private var agentCollapsedHeader: some View {
    ZStack(alignment: .bottomTrailing) {
        Image(systemName: "terminal")
            .font(.system(size: 27, weight: .bold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 64, height: 64)

        Circle()
            .fill(agentStatusColor)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.92), lineWidth: 2)
            }
            .offset(x: 1, y: 1)
    }
    .frame(width: 64, height: 64)
}
```

Add `agentStatusColor`:

```swift
private var agentStatusColor: Color {
    switch agentStore.snapshot.activityStatus {
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
```

- [ ] **Step 6: Run tests and build**

Run: `swift test`

Expected: PASS.

Run: `make build`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/FloatMon/Support/WindowDragBridge.swift Sources/FloatMon/Support/Formatters.swift Sources/FloatMon/Views/IslandView.swift Sources/FloatMon/Views/AgentMonitorView.swift
git commit -m "feat: add agent monitor UI"
```

---

### Task 7: End-To-End Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the agent monitor MVP**

Add to `README.md` after the introductory paragraph:

```markdown
## Agent Monitoring

Double-click the floating ball to switch between app monitoring and agent monitoring.
The current MVP monitors Codex. On startup, FloatMon can register a Codex hook after
confirmation. Before editing `~/.codex/hooks.json`, it writes a timestamped backup
next to the original file.
```

- [ ] **Step 2: Run full verification**

Run: `swift test`

Expected: PASS.

Run: `make build`

Expected: PASS.

- [ ] **Step 3: Inspect hook registration manually without modifying real hooks**

Run: `swift test --filter CodexHookRegistrationServiceTests`

Expected: PASS. This proves backup and merge behavior using temporary directories.

- [ ] **Step 4: Check git diff**

Run: `git diff --stat HEAD`

Expected: only README changes since the previous commit.

- [ ] **Step 5: Commit docs**

```bash
git add README.md
git commit -m "docs: describe agent monitoring"
```

---

## Self-Review

Spec coverage:

- Double-click mode switching: Task 6.
- Preserve existing app monitor: Task 6 only adds mode branching and keeps `ExpandedProcessList`.
- Multi-agent architecture with Codex MVP: Task 1 models use `AgentProvider`; Tasks 2-4 implement Codex only.
- Startup hook prompt: Task 5.
- Backup before hook registration: Task 2 tests and service.
- Hook event files and sqlite snapshot: Tasks 3 and 4.
- Error handling for missing files and malformed events: Task 4 tests and reader.
- README update: Task 7.

Placeholder scan: no unresolved placeholders or references to undefined tasks remain.

Type consistency: `AgentProvider`, `AgentEvent`, `AgentSnapshot`, `CodexPaths`, `CodexHookRegistrationService`, `CodexHookWriter`, `CodexSnapshotReader`, and `AgentStore` are introduced before use in later tasks.
