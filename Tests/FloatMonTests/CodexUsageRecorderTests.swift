import XCTest
@testable import FloatMon

final class CodexUsageRecorderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatMonUsageTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testRecordsOnlyPositiveTokenDeltasAfterBaseline() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 12)))
        let recorder = CodexUsageRecorder(paths: testPaths, now: { now })

        try recorder.record(samples: [
            CodexThreadTokenSample(id: "thread-1", tokensUsed: 100, updatedAtMS: milliseconds(for: now)),
            CodexThreadTokenSample(id: "thread-2", tokensUsed: 50, updatedAtMS: milliseconds(for: now))
        ])
        var summary = try XCTUnwrap(recorder.readSummary(dayCount: 7))
        XCTAssertEqual(summary.totalTokens, 0)
        XCTAssertEqual(summary.threadCount, 2)
        XCTAssertEqual(summary.todayTokens, 0)
        XCTAssertEqual(summary.averageTokensPerDay, 0)
        XCTAssertNil(summary.lastCapturedAt)

        try recorder.record(samples: [
            CodexThreadTokenSample(id: "thread-1", tokensUsed: 175, updatedAtMS: milliseconds(for: now)),
            CodexThreadTokenSample(id: "thread-2", tokensUsed: 40, updatedAtMS: milliseconds(for: now)),
            CodexThreadTokenSample(id: "thread-3", tokensUsed: 200, updatedAtMS: milliseconds(for: now))
        ])
        summary = try XCTUnwrap(recorder.readSummary(dayCount: 7))

        XCTAssertEqual(summary.totalTokens, 75)
        XCTAssertEqual(summary.threadCount, 3)
        XCTAssertEqual(summary.peakTokens, 75)
        XCTAssertEqual(summary.todayTokens, 75)
        XCTAssertEqual(summary.averageTokensPerDay, 11)
        XCTAssertEqual(summary.lastCapturedAt, now)
        XCTAssertEqual(summary.buckets.map(\.tokensUsed), [0, 0, 0, 0, 0, 0, 75])
        XCTAssertEqual(summary.buckets.map(\.threadCount), [0, 0, 0, 0, 0, 0, 1])
    }

    func testRecordsDeltasIntoCurrentCaptureDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 23)))
        let secondDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 1)))
        var currentDate = firstDay
        let recorder = CodexUsageRecorder(paths: testPaths, now: { currentDate })

        try recorder.record(samples: [
            CodexThreadTokenSample(id: "thread-1", tokensUsed: 100, updatedAtMS: milliseconds(for: firstDay))
        ])
        try recorder.record(samples: [
            CodexThreadTokenSample(id: "thread-1", tokensUsed: 125, updatedAtMS: milliseconds(for: firstDay))
        ])
        currentDate = secondDay
        try recorder.record(samples: [
            CodexThreadTokenSample(id: "thread-1", tokensUsed: 175, updatedAtMS: milliseconds(for: secondDay))
        ])

        let summary = try XCTUnwrap(recorder.readSummary(dayCount: 2))

        XCTAssertEqual(summary.totalTokens, 75)
        XCTAssertEqual(summary.todayTokens, 50)
        XCTAssertEqual(summary.averageTokensPerDay, 38)
        XCTAssertEqual(summary.lastCapturedAt, secondDay)
        XCTAssertEqual(summary.buckets.map(\.tokensUsed), [25, 50])
    }

    private var testPaths: CodexPaths {
        CodexPaths(
            codexHome: root.appendingPathComponent(".codex", isDirectory: true),
            floatMonHome: root.appendingPathComponent(".floatmon", isDirectory: true)
        )
    }

    private func milliseconds(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 * 1000)
    }
}
