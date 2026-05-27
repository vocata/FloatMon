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
