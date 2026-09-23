import Foundation
import XCTest
import NinhoWidgetSupport
@testable import NinhoCore

final class WidgetSummaryTests: XCTestCase, @unchecked Sendable {
    private var now: Date { date("2026-09-23T12:00:00Z") }
    private var utc: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ text: String) -> Date { StudyEngine.parseTimestamp(text)! }
    private func session(_ timestamp: String, minutes: Double = 10, kind: SessionKind = .focus) -> StudySession {
        StudySession(durationMinutes: minutes, completedAt: timestamp, kind: kind)
    }
    func testStreakUsesCalendarDaysAndKeepsYesterdayUntilMidnight() throws {
        let state = AppState(sessions: [session("2026-09-21T12:00:00Z"), session("2026-09-22T20:00:00Z")])
        let summary = WidgetSummary.make(state: state, at: now, calendar: utc)
        try summary.validate()
        XCTAssertEqual(summary.moment(at: now, timeZone: utc.timeZone)?.streak, 2)
        XCTAssertEqual(summary.moment(at: date("2026-09-24T00:00:00Z"), timeZone: utc.timeZone)?.streak, 0)
        XCTAssertEqual(StudyEngine.overview(in: state, at: now, calendar: utc).streak, summary.moments[0].streak)
    }
    func testZeroFocusFutureSessionsAndOpenTimerCannotCreateAStreak() throws {
        let state = AppState(sessions: [session("2026-09-23T13:00:00Z"), session("2026-09-23T10:00:00Z", minutes: 0)])
        var focus = FocusTimer(); try focus.start(at: now)
        let summary = WidgetSummary.make(state: state, focus: focus, at: now, calendar: utc)
        XCTAssertTrue(summary.moments.allSatisfy { $0.streak == 0 && $0.todayMinutes == 0 })
        XCTAssertFalse(summary.moments[0].studiedToday)
    }
    func testARecordedReviewCountsAndDuplicateSessionsDoNotDuplicateTheDay() {
        let state = AppState(sessions: [session("2026-09-23T10:00:00Z", minutes: 0, kind: .review), session("2026-09-23T11:00:00Z", minutes: 0, kind: .review)])
        let summary = WidgetSummary.make(state: state, at: now, calendar: utc)
        XCTAssertEqual(summary.moments[0].streak, 1)
        XCTAssertTrue(summary.moments[0].studiedToday)
        XCTAssertEqual(summary.moments[0].todayMinutes, 0)
    }
    func testMidnightUsesLocalCalendarAcrossDSTRatherThan24Hours() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let before = date("2026-03-08T05:15:00Z")
        let state = AppState(sessions: [session("2026-03-07T18:00:00Z"), session("2026-03-08T05:10:00Z")])
        let summary = WidgetSummary.make(state: state, at: before, calendar: calendar)
        let midnight = date("2026-03-09T04:00:00Z")
        XCTAssertTrue(summary.moments.contains { $0.date == midnight })
        XCTAssertEqual(summary.moment(at: midnight, timeZone: calendar.timeZone)?.streak, 2)
        XCTAssertEqual(summary.moment(at: midnight, timeZone: calendar.timeZone)?.todayMinutes, 0)
        XCTAssertNil(summary.moment(at: midnight, timeZone: utc.timeZone))
    }
    func testReviewDueTimeHasAnEntryWithoutOpeningTheDatabaseInWidget() throws {
        let due = date("2026-09-23T14:00:00Z")
        let state = AppState(cards: [ReviewCard(id: "card", question: "Private question", answer: "Private answer", dueAt: StudyEngine.timestamp(due), lastReviewedAt: "2026-09-22T10:00:00Z")])
        let summary = WidgetSummary.make(state: state, at: now, calendar: utc)
        XCTAssertEqual(summary.moments[0].dueReviews, 0)
        XCTAssertEqual(summary.moment(at: due, timeZone: utc.timeZone)?.dueReviews, 1)
        XCTAssertTrue(summary.moments.contains { $0.date == due })
    }
    func testRunningCountdownEndsWithoutCreditingUnsavedStudy() throws {
        var focus = FocusTimer(); try focus.configure(subjectId: "", minutes: 5); try focus.start(at: now)
        let summary = WidgetSummary.make(state: AppState(), focus: focus, at: now, calendar: utc)
        let end = now.addingTimeInterval(300)
        XCTAssertEqual(summary.moments[0].focusEndsAt, end)
        let ended = try XCTUnwrap(summary.moment(at: end, timeZone: utc.timeZone))
        XCTAssertEqual(ended.focusState, "ready"); XCTAssertNil(ended.focusEndsAt)
        XCTAssertEqual(ended.streak, 0); XCTAssertEqual(ended.todayMinutes, 0)
        XCTAssertEqual(ended.focusMinutes, 5)
    }
    func testExpiredUnreconciledTimerHasAValidSnapshotWithoutPastEntries() throws {
        var focus = FocusTimer(); try focus.configure(subjectId: "", minutes: 5); try focus.start(at: now.addingTimeInterval(-600))
        let summary = WidgetSummary.make(state: AppState(), focus: focus, at: now, calendar: utc)
        try summary.validate()
        XCTAssertEqual(summary.moments.first?.date, now)
        XCTAssertTrue(summary.moments.allSatisfy { $0.focusState == "ready" && $0.streak == 0 && $0.todayMinutes == 0 })
    }
    func testAggregatedReviewCountsMatchQueueAndDailyNewBudgetResets() throws {
        let tracked = StudySession(id: "review:first:tracked", completedAt: StudyEngine.timestamp(now), kind: .review)
        let settings = Settings(newCardsPerDay: 3)
        let cards = [
            ReviewCard(id: "tracked", dueAt: StudyEngine.timestamp(now), lastReviewedAt: StudyEngine.timestamp(now), repetitions: 1),
            ReviewCard(id: "legacy", dueAt: StudyEngine.timestamp(now), lastReviewedAt: StudyEngine.timestamp(now), repetitions: 1),
            ReviewCard(id: "suspended", dueAt: StudyEngine.timestamp(now), suspended: true)
        ] + (0..<5).map { ReviewCard(id: "new-\($0)", dueAt: StudyEngine.timestamp(now.addingTimeInterval(Double($0) * 60))) }
        let state = AppState(settings: settings, cards: cards, sessions: [tracked])
        let summary = WidgetSummary.make(state: state, at: now, calendar: utc)
        for moment in summary.moments { XCTAssertEqual(moment.dueReviews, StudyEngine.dueCards(in: state, at: moment.date, calendar: utc).count) }
        XCTAssertEqual(summary.moments[0].dueReviews, 3)
        XCTAssertEqual(summary.moment(at: date("2026-09-24T00:00:00Z"), timeZone: utc.timeZone)?.dueReviews, 5)
    }
    func testPausedTimerNeverCountsDownOrAddsMinutes() throws {
        var focus = FocusTimer(); try focus.configure(subjectId: "", minutes: 5); try focus.start(at: now.addingTimeInterval(-60)); try focus.pause(at: now)
        let summary = WidgetSummary.make(state: AppState(), focus: focus, at: now, calendar: utc)
        XCTAssertTrue(summary.moments.allSatisfy { $0.focusState == "paused" && $0.focusEndsAt == nil && $0.focusRemainingSeconds == 240 && $0.todayMinutes == 0 })
    }
    func testSummaryIsBoundedAndContainsNoPrivateTextOrIDs() throws {
        var state = AppState(settings: Settings(name: "PRIVATE NAME"))
        state.sessions = [StudySession(id: "PRIVATE SESSION", subjectId: "PRIVATE SUBJECT", durationMinutes: 10, completedAt: StudyEngine.timestamp(now))]
        state.cards = (0..<100).map { ReviewCard(id: "PRIVATE CARD \($0)", question: "PRIVATE QUESTION", answer: "PRIVATE ANSWER", dueAt: StudyEngine.timestamp(now.addingTimeInterval(Double($0 + 1) * 10))) }
        let summary = WidgetSummary.make(state: state, at: now, calendar: utc)
        try summary.validate()
        let data = try JSONEncoder().encode(summary)
        XCTAssertLessThan(summary.moments.count, 64)
        XCTAssertLessThan(data.count, WidgetSnapshotFile.maximumBytes)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE"))
        XCTAssertNil(summary.moment(at: now.addingTimeInterval(490), timeZone: utc.timeZone))
    }
    func testExpiredOrFutureSummaryDoesNotPretendToBeCurrent() {
        let summary = WidgetSummary.make(state: AppState(), at: now, calendar: utc)
        XCTAssertNil(summary.moment(at: summary.validUntil, timeZone: utc.timeZone))
        XCTAssertNil(summary.moment(at: now.addingTimeInterval(-1), timeZone: utc.timeZone))
    }
    func testFileRoundTripAndInvalidWritePreservePreviousValidSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = WidgetSummary.make(state: AppState(), at: now, calendar: utc)
        try WidgetSnapshotFile.write(snapshot, in: root)
        XCTAssertEqual(try WidgetSnapshotFile.read(in: root), snapshot)
        var invalid = snapshot; invalid.schema = 999
        XCTAssertThrowsError(try WidgetSnapshotFile.write(invalid, in: root))
        XCTAssertEqual(try WidgetSnapshotFile.read(in: root), snapshot)
        invalid = snapshot; invalid.moments[0].streak = -1
        XCTAssertThrowsError(try invalid.validate())
    }
    func testCorruptAndOversizedWidgetFilesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(WidgetSnapshotFile.name)
        try Data("not JSON".utf8).write(to: file)
        XCTAssertThrowsError(try WidgetSnapshotFile.read(in: root))
        try Data(repeating: 32, count: WidgetSnapshotFile.maximumBytes + 1).write(to: file)
        XCTAssertThrowsError(try WidgetSnapshotFile.read(in: root))
    }
}
