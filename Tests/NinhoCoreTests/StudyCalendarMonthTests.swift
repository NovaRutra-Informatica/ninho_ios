import Foundation
import XCTest
@testable import NinhoCore

final class StudyCalendarMonthTests: XCTestCase {
    private func date(_ value: String) -> Date { StudyEngine.parseTimestamp(value)! }
    private var utc: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }

    func testHistoryIncludesEarlierMonthsEvenAfterStreakBreaksAndRejectsUnsavedFutureAndInvalidSessions() {
        let now = date("2026-09-23T12:00:00Z")
        let sessions = [
            StudySession(durationMinutes: 20, completedAt: "2026-08-10T12:00:00Z"),
            StudySession(durationMinutes: 10, completedAt: "2026-09-01T12:00:00Z"),
            StudySession(durationMinutes: 10, completedAt: "2026-09-01T14:00:00Z"),
            StudySession(durationMinutes: 0, completedAt: "2026-09-02T12:00:00Z", kind: .review),
            StudySession(durationMinutes: 0, completedAt: "2026-09-03T12:00:00Z"),
            StudySession(durationMinutes: -1, completedAt: "2026-09-04T12:00:00Z", kind: .review),
            StudySession(durationMinutes: .infinity, completedAt: "2026-09-05T12:00:00Z"),
            StudySession(durationMinutes: 30, completedAt: "2026-09-24T12:00:00Z"),
            StudySession(durationMinutes: 5, completedAt: "invalid")
        ]
        let active = StudyStreak.activeDays(in: sessions, at: now, calendar: utc)
        XCTAssertEqual(active, ["2026-08-10", "2026-09-01", "2026-09-02"])
        XCTAssertEqual(StudyStreak.current(activeDays: active, at: now, calendar: utc), 0)
        let september = StudyCalendarMonth(containing: now, activeDays: active, at: now, calendar: utc)
        XCTAssertEqual(september.studiedDays, 2)
        XCTAssertEqual(september.days.filter(\.isToday).map(\.number), [23])
        XCTAssertTrue(september.days.filter { $0.number > 23 }.allSatisfy(\.isFuture))
        let august = StudyCalendarMonth(containing: date("2026-08-15T12:00:00Z"), activeDays: active, at: now, calendar: utc)
        XCTAssertEqual(august.days.filter(\.studied).map(\.number), [10])
    }

    func testMonthGridHandlesLeapDayAndDifferentFirstWeekdays() {
        let now = date("2024-03-01T12:00:00Z"), february = date("2024-02-28T12:00:00Z")
        var sunday = utc; sunday.firstWeekday = 1
        var monday = utc; monday.firstWeekday = 2
        let a = StudyCalendarMonth(containing: february, activeDays: ["2024-02-29"], at: now, calendar: sunday)
        let b = StudyCalendarMonth(containing: february, activeDays: ["2024-02-29"], at: now, calendar: monday)
        XCTAssertEqual(a.days.count, 29); XCTAssertEqual(a.leadingEmptyDays, 4)
        XCTAssertEqual(b.leadingEmptyDays, 3)
        XCTAssertEqual(a.days.last?.id, "2024-02-29"); XCTAssertEqual(a.studiedDays, 1)
        let nonLeap = StudyCalendarMonth(containing: date("2025-02-10T12:00:00Z"), activeDays: [], at: now, calendar: utc)
        XCTAssertEqual(nonLeap.days.count, 28)
        XCTAssertTrue(nonLeap.days.allSatisfy(\.isFuture))
    }

    func testCalendarDaysMatchOverviewAndWidgetsAcrossLocalMidnightAndDST() {
        var calendar = utc; calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date("2026-03-09T04:15:00Z")
        let state = AppState(sessions: [
            StudySession(durationMinutes: 10, completedAt: "2026-03-08T04:30:00Z"),
            StudySession(durationMinutes: 0, completedAt: "2026-03-09T03:30:00Z", kind: .review)
        ])
        let active = StudyStreak.activeDays(in: state.sessions, at: now, calendar: calendar)
        XCTAssertEqual(active, ["2026-03-07", "2026-03-08"])
        let month = StudyCalendarMonth(containing: now, activeDays: active, at: now, calendar: calendar)
        XCTAssertEqual(month.days.filter(\.studied).map(\.number), [7, 8])
        XCTAssertEqual(month.days.first { $0.isToday }?.number, 9)
        let streak = StudyStreak.current(activeDays: active, at: now, calendar: calendar)
        XCTAssertEqual(streak, 2)
        XCTAssertEqual(streak, StudyEngine.overview(in: state, at: now, calendar: calendar).streak)
        XCTAssertEqual(streak, WidgetSummary.make(state: state, at: now, calendar: calendar).moments[0].streak)
    }

    func testFutureKeysNeverMarkAnUnstudiedDayAndYearBoundaryHasCorrectGeometry() {
        let now = date("2026-01-01T12:00:00Z")
        let month = StudyCalendarMonth(containing: now, activeDays: ["2025-12-31", "2026-01-02"], at: now, calendar: utc)
        XCTAssertEqual(month.days.count, 31)
        XCTAssertEqual(month.days.first?.id, "2026-01-01")
        XCTAssertEqual(month.studiedDays, 0)
        XCTAssertTrue(month.days[1].isFuture)
    }
}
