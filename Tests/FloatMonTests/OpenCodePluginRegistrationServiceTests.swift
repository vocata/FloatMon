import XCTest
@testable import FloatMon

final class OpenCodePluginRegistrationServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonOpenCodePluginTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testRegisterInstallsGlobalPluginForCodexEquivalentNativeOpenCodeEvents() throws {
        let service = OpenCodePluginRegistrationService(paths: testPaths)

        let result = try service.register(executablePath: "/tmp/FloatMon")

        XCTAssertNil(result.backupURL)
        let plugin = try String(contentsOf: testPaths.openCodePluginJS, encoding: .utf8)
        XCTAssertTrue(plugin.contains("FLOATMON_OPENCODE_PLUGIN"))
        XCTAssertTrue(plugin.contains("--floatmon-opencode-hook"))
        XCTAssertTrue(plugin.contains("event: async"))
        XCTAssertTrue(plugin.contains("FLOATMON_EVENT_TYPES"))
        [
            "session.created",
            "session.status",
            "tool.execute.before",
            "permission.asked",
            "tool.execute.after",
            "session.compacted",
            "session.error"
        ].forEach { eventType in
            XCTAssertTrue(plugin.contains(#""\#(eventType)""#), "Missing \(eventType)")
        }
        XCTAssertFalse(plugin.contains(#""session.idle""#))
        XCTAssertFalse(plugin.contains("message.updated"))
        XCTAssertTrue(service.isRegistered(executablePath: "/tmp/FloatMon"))
    }

    func testOldPluginWithoutStatusFilterIsNotRegistered() throws {
        try FileManager.default.createDirectory(
            at: testPaths.openCodePluginsDirectory,
            withIntermediateDirectories: true
        )
        try """
        // FLOATMON_OPENCODE_PLUGIN
        const FLOATMON_EXECUTABLE = "/tmp/FloatMon"
        function sendFloatMonEvent(eventType, payload) {
          spawn(FLOATMON_EXECUTABLE, ["--floatmon-opencode-hook", eventType])
        }
        export const FloatMonOpenCodePlugin = async () => ({
          event: async ({ event }) => {
            await sendFloatMonEvent(event.type, { event })
          }
        })
        """.write(to: testPaths.openCodePluginJS, atomically: true, encoding: .utf8)
        let service = OpenCodePluginRegistrationService(paths: testPaths)

        XCTAssertFalse(service.isRegistered(executablePath: "/tmp/FloatMon"))
    }

    func testRegisterBacksUpExistingPluginBeforeReplacingIt() throws {
        try FileManager.default.createDirectory(
            at: testPaths.openCodePluginsDirectory,
            withIntermediateDirectories: true
        )
        try "existing plugin".write(to: testPaths.openCodePluginJS, atomically: true, encoding: .utf8)
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let service = OpenCodePluginRegistrationService(paths: testPaths, now: { fixedNow })

        let result = try service.register(executablePath: "/tmp/FloatMon")

        let backupURL = try XCTUnwrap(result.backupURL)
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("floatmon-opencode-plugin.floatmon-backup."))
        XCTAssertEqual(backupURL.pathExtension, "bak")
        XCTAssertTrue(backupURL.path.hasPrefix(testPaths.openCodePluginsDirectory.path))
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "existing plugin")
    }

    func testDetachRemovesFloatMonPluginAndCreatesBackup() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let service = OpenCodePluginRegistrationService(paths: testPaths, now: { fixedNow })
        _ = try service.register(executablePath: "/tmp/FloatMon")

        let result = try service.detach()

        let backupURL = try XCTUnwrap(result.backupURL)
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("floatmon-opencode-plugin.floatmon-unregister-backup."))
        XCTAssertEqual(backupURL.pathExtension, "bak")
        XCTAssertTrue(backupURL.path.hasPrefix(testPaths.openCodePluginsDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPaths.openCodePluginJS.path))
    }

    private var testPaths: CodexPaths {
        CodexPaths(
            codexHome: root.appendingPathComponent(".codex", isDirectory: true),
            floatMonHome: root.appendingPathComponent(".floatmon", isDirectory: true),
            openCodeConfigHome: root
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("opencode", isDirectory: true),
            openCodeDataHome: root
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
                .appendingPathComponent("opencode", isDirectory: true)
        )
    }
}
