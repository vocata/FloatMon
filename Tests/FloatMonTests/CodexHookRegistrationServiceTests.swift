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

    func testRegisterInstallsAllSupportedCodexHooks() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try #"{"hooks":{}}"#.write(to: hooksURL, atomically: true, encoding: .utf8)
        let service = CodexHookRegistrationService(paths: CodexPaths(codexHome: root))

        _ = try service.register(executablePath: "/tmp/FloatMon")

        let output = try String(contentsOf: hooksURL, encoding: .utf8)
        [
            "PreToolUse",
            "PermissionRequest",
            "PostToolUse",
            "PreCompact",
            "PostCompact",
            "SessionStart",
            "UserPromptSubmit",
            "SubagentStart",
            "SubagentStop",
            "Stop"
        ].forEach { event in
            XCTAssertTrue(output.contains("--floatmon-codex-hook \(event)"), "Missing \(event)")
        }
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

    func testRegisterRemovesStaleFloatMonHooksForSameEvent() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "command": "'/tmp/old/FloatMon' --floatmon-codex-hook Stop",
                    "type": "command",
                    "timeout": 5
                  }
                ]
              },
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

        _ = try service.register(executablePath: "/tmp/current/FloatMon")

        let output = try String(contentsOf: hooksURL, encoding: .utf8)
        XCTAssertFalse(output.contains("'/tmp/old/FloatMon' --floatmon-codex-hook Stop"))
        XCTAssertTrue(output.contains("echo existing"))
        XCTAssertEqual(output.components(separatedBy: "--floatmon-codex-hook Stop").count - 1, 1)
    }

    func testDetachRemovesFloatMonHooksAndPreservesExistingHooks() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "command": "echo existing stop",
                    "type": "command",
                    "timeout": 5
                  }
                ]
              },
              {
                "hooks": [
                  {
                    "command": "'/tmp/FloatMon' --floatmon-codex-hook Stop",
                    "type": "command",
                    "timeout": 5
                  }
                ]
              }
            ],
            "SubagentStart": [
              {
                "hooks": [
                  {
                    "command": "'/tmp/FloatMon' --floatmon-codex-hook SubagentStart",
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

        let result = try service.detach()

        XCTAssertTrue(result.backupURL.lastPathComponent.hasPrefix("hooks.floatmon-unregister-backup."))
        let output = try String(contentsOf: hooksURL, encoding: .utf8)
        XCTAssertTrue(output.contains("echo existing stop"))
        XCTAssertFalse(output.contains("--floatmon-codex-hook"))
        XCTAssertFalse(output.contains("SubagentStart"))
    }

    func testIsRegisteredMatchesEscapedExecutablePath() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try #"{"hooks":{}}"#.write(to: hooksURL, atomically: true, encoding: .utf8)
        let executablePath = "/tmp/O'Brien/FloatMon"
        let service = CodexHookRegistrationService(paths: CodexPaths(codexHome: root))

        _ = try service.register(executablePath: executablePath)

        XCTAssertTrue(service.isRegistered(executablePath: executablePath))
    }

    func testRegisterUsesDistinctBackupURLWhenTimestampCollides() throws {
        let hooksURL = root.appendingPathComponent("hooks.json")
        try #"{"hooks":{}}"#.write(to: hooksURL, atomically: true, encoding: .utf8)
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let paths = CodexPaths(codexHome: root)
        let firstBackupURL = paths.backupHooksURL(now: fixedNow)
        try "existing backup".write(to: firstBackupURL, atomically: true, encoding: .utf8)
        let service = CodexHookRegistrationService(paths: paths, now: { fixedNow })

        let result = try service.register(executablePath: "/tmp/FloatMon")

        XCTAssertNotEqual(result.backupURL, firstBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupURL.path))
    }
}
