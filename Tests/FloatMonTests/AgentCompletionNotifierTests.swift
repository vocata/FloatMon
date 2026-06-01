import XCTest
@testable import FloatMon

final class AgentCompletionNotifierTests: XCTestCase {
    func testSeedsExistingStopEventsWithoutShowingNotice() {
        var notifier = AgentCompletionNotifier()
        let oldStop = event(type: "Stop", timestamp: 10, threadID: "thread-1", message: "done")
        let snapshot = snapshot(events: [oldStop])

        let notice = notifier.notice(for: snapshot)

        XCTAssertNil(notice)
    }

    func testShowsNoticeForNewStopEventOnlyOnce() throws {
        var notifier = AgentCompletionNotifier()
        let oldStop = event(type: "Stop", timestamp: 10, threadID: "thread-1", message: "old")
        XCTAssertNil(notifier.notice(for: snapshot(events: [oldStop])))

        let newStop = event(type: "Stop", timestamp: 20, threadID: "thread-2", message: "new")
        let firstNotice = try XCTUnwrap(notifier.notice(for: snapshot(events: [newStop, oldStop])))
        let secondNotice = notifier.notice(for: snapshot(events: [newStop, oldStop]))

        XCTAssertEqual(firstNotice.id, newStop.id)
        XCTAssertNil(secondNotice)
    }

    func testIgnoresNonStopEvents() {
        var notifier = AgentCompletionNotifier()
        let toolEvent = event(type: "PostToolUse", timestamp: 20, threadID: "thread-1", detail: "git status")
        let snapshot = snapshot(events: [toolEvent])

        let notice = notifier.notice(for: snapshot)

        XCTAssertNil(notice)
    }

    func testReturnsNoticeForStopWithoutMessage() throws {
        var notifier = AgentCompletionNotifier()
        XCTAssertNil(notifier.notice(for: snapshot(events: [])))
        let stop = event(type: "Stop", timestamp: 20, threadID: "thread-1")

        let notice = try XCTUnwrap(notifier.notice(for: snapshot(events: [stop], threadID: "thread-1")))

        XCTAssertEqual(notice.id, stop.id)
    }

    func testShowsNoticeForNewStopEvenWhenHookStatusHasNotBeenChecked() throws {
        var notifier = AgentCompletionNotifier()
        XCTAssertNil(notifier.notice(for: snapshot(events: [], hookStatus: .unknown)))
        let stop = event(type: "Stop", timestamp: 20, threadID: "thread-1", message: "done")

        let notice = try XCTUnwrap(notifier.notice(for: snapshot(events: [stop], hookStatus: .unknown)))

        XCTAssertEqual(notice.id, stop.id)
    }

    func testKeepsNoticeWhenCompletionEventIsStillLatestEvent() {
        let notifier = AgentCompletionNotifier()
        let stop = event(type: "Stop", timestamp: 20, threadID: "thread-1")
        let notice = AgentCompletionNotice(id: stop.id)

        XCTAssertFalse(notifier.shouldDismiss(notice, for: snapshot(events: [stop])))
    }

    func testDismissesNoticeWhenNewerEventArrives() {
        let notifier = AgentCompletionNotifier()
        let stop = event(type: "Stop", timestamp: 20, threadID: "thread-1")
        let newerEvent = event(type: "PreToolUse", timestamp: 30, threadID: "thread-1")
        let notice = AgentCompletionNotice(id: stop.id)

        XCTAssertTrue(notifier.shouldDismiss(notice, for: snapshot(events: [newerEvent, stop])))
    }

    private func event(
        type: String,
        timestamp: TimeInterval,
        threadID: String?,
        detail: String? = nil,
        message: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            provider: .codex,
            type: type,
            timestamp: Date(timeIntervalSince1970: timestamp),
            threadID: threadID,
            toolName: nil,
            detail: detail,
            message: message
        )
    }

    private func snapshot(
        events: [AgentEvent],
        threadID: String? = nil,
        hookStatus: AgentHookStatus = .registered
    ) -> AgentSnapshot {
        AgentSnapshot(
            provider: .codex,
            latestEventType: events.first?.type,
            hookStatus: hookStatus,
            currentThread: threadID.map {
                AgentThreadSummary(
                    id: $0,
                    title: "Refactor parser",
                    cwd: "/tmp/float_mon",
                    tokensUsed: 123,
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            },
            currentGoal: nil,
            usageSummary: nil,
            recentEvents: events,
            lastUpdated: Date(timeIntervalSince1970: 20),
            unavailableReason: nil
        )
    }
}
