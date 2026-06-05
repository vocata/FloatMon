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

    func testShowsNoticeForNewOpenCodeIdleStatusOnlyOnce() throws {
        var notifier = AgentCompletionNotifier()
        let oldIdle = event(provider: .opencode, type: "session.status", timestamp: 10, threadID: "session-1", detail: "idle")
        XCTAssertNil(notifier.notice(for: snapshot(provider: .opencode, events: [oldIdle])))

        let newIdle = event(provider: .opencode, type: "session.status", timestamp: 20, threadID: "session-2", detail: "idle")
        let firstNotice = try XCTUnwrap(notifier.notice(for: snapshot(provider: .opencode, events: [newIdle, oldIdle])))
        let secondNotice = notifier.notice(for: snapshot(provider: .opencode, events: [newIdle, oldIdle]))

        XCTAssertEqual(firstNotice.id, newIdle.id)
        XCTAssertNil(secondNotice)
    }

    func testSeedsEachProviderIndependentlyBeforeShowingCompletionNotice() throws {
        var notifier = AgentCompletionNotifier()
        let codexStop = event(type: "Stop", timestamp: 10, threadID: "thread-1")
        XCTAssertNil(notifier.notice(for: snapshot(events: [codexStop])))

        let oldOpenCodeIdle = event(provider: .opencode, type: "session.status", timestamp: 20, threadID: "session-1", detail: "idle")
        XCTAssertNil(notifier.notice(for: snapshot(provider: .opencode, events: [oldOpenCodeIdle])))

        let newOpenCodeIdle = event(provider: .opencode, type: "session.status", timestamp: 30, threadID: "session-2", detail: "idle")
        let notice = try XCTUnwrap(notifier.notice(for: snapshot(provider: .opencode, events: [newOpenCodeIdle, oldOpenCodeIdle])))

        XCTAssertEqual(notice.id, newOpenCodeIdle.id)
    }

    func testIgnoresOpenCodeBusyStatusForCompletionNotice() {
        var notifier = AgentCompletionNotifier()
        XCTAssertNil(notifier.notice(for: snapshot(provider: .opencode, events: [])))
        let busy = event(provider: .opencode, type: "session.status", timestamp: 20, threadID: "session-1", detail: "busy")

        XCTAssertNil(notifier.notice(for: snapshot(provider: .opencode, events: [busy])))
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
        provider: AgentProvider = .codex,
        type: String,
        timestamp: TimeInterval,
        threadID: String?,
        detail: String? = nil,
        message: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            provider: provider,
            type: type,
            timestamp: Date(timeIntervalSince1970: timestamp),
            threadID: threadID,
            toolName: nil,
            detail: detail,
            message: message
        )
    }

    private func snapshot(
        provider: AgentProvider = .codex,
        events: [AgentEvent],
        threadID: String? = nil,
        hookStatus: AgentHookStatus = .registered
    ) -> AgentSnapshot {
        AgentSnapshot(
            provider: provider,
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
