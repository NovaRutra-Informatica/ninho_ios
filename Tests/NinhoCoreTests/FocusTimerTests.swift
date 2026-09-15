import Foundation
import XCTest
@testable import NinhoCore

final class FocusTimerTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private func timer(minutes: Double = 25) throws -> FocusTimer {
        var value = FocusTimer()
        try value.configure(subjectId: "subject", lessonId: "lesson", minutes: minutes)
        return value
    }

    func testNewTimerHasNoInventedProgress() throws {
        let value = FocusTimer()
        XCTAssertEqual(value.phase, .idle)
        XCTAssertFalse(value.isRunning)
        XCTAssertEqual(value.elapsedSeconds(at: epoch), 0)
        XCTAssertEqual(value.remainingSeconds(at: epoch), 1500)
        XCTAssertNil(value.pendingSession)
    }

    func testBackgroundElapsedIsRecoveredWithoutTicks() throws {
        var value = try timer()
        try value.start(at: epoch)
        let recovered = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(recovered.phase, .running)
        XCTAssertEqual(recovered.elapsedSeconds(at: epoch.addingTimeInterval(123)), 123)
        XCTAssertEqual(recovered.snapshot.subjectId, "subject")
        XCTAssertEqual(recovered.snapshot.lessonId, "lesson")
        XCTAssertEqual(recovered.snapshot.sessionId, value.snapshot.sessionId)
    }

    func testPauseAndResumeCountOnlyActiveSegments() throws {
        var value = try timer()
        try value.start(at: epoch)
        try value.pause(at: epoch.addingTimeInterval(30))
        XCTAssertEqual(value.phase, .paused)
        XCTAssertEqual(value.elapsedSeconds(at: epoch.addingTimeInterval(300)), 30)
        var recovered = try FocusTimer(snapshot: JSONDecoder().decode(FocusSnapshot.self, from: JSONEncoder().encode(value.snapshot)))
        try recovered.resume(at: epoch.addingTimeInterval(400))
        XCTAssertEqual(recovered.elapsedSeconds(at: epoch.addingTimeInterval(420)), 50)
        XCTAssertEqual(recovered.snapshot.sessionId, value.snapshot.sessionId)
    }

    func testRunningContextCannotChangeEvenBeforeFirstSecond() throws {
        var value = try timer()
        try value.start(at: epoch)
        let saved = value
        XCTAssertThrowsError(try value.configure(subjectId: "other", lessonId: "else", minutes: 25))
        XCTAssertEqual(value, saved)
        try value.configure(subjectId: "subject", lessonId: "lesson", minutes: 25)
        XCTAssertEqual(value, saved)
    }

    func testPausedContextAndDurationRemainLocked() throws {
        var value = try timer()
        try value.start(at: epoch)
        try value.pause(at: epoch.addingTimeInterval(10))
        XCTAssertThrowsError(try value.configure(subjectId: "subject", lessonId: "other", minutes: 25))
        XCTAssertThrowsError(try value.configure(subjectId: "subject", lessonId: "lesson", minutes: 30))
        XCTAssertEqual(value.snapshot.lessonId, "lesson")
        XCTAssertEqual(value.snapshot.targetSeconds, 1500)
    }

    func testResetDiscardsUnfinishedTimeAndRenewsID() throws {
        var value = try timer()
        try value.start(at: epoch)
        try value.pause(at: epoch.addingTimeInterval(90))
        let oldID = value.snapshot.sessionId
        try value.reset()
        XCTAssertEqual(value.phase, .idle)
        XCTAssertNotEqual(value.snapshot.sessionId, oldID)
        XCTAssertEqual(value.snapshot.lessonId, "lesson")
        XCTAssertNil(try value.finish(at: epoch.addingTimeInterval(100)))
        try value.configure(subjectId: "other", lessonId: "other-lesson", minutes: 10)
        XCTAssertEqual(value.snapshot.lessonId, "other-lesson")
    }

    func testFinishingHasStableDurablePendingSessionUntilAcknowledged() throws {
        var value = try timer()
        try value.start(at: epoch)
        let first = try XCTUnwrap(value.finish(at: epoch.addingTimeInterval(90)))
        XCTAssertEqual(first.durationMinutes, 1.5)
        XCTAssertEqual(first.lessonId, "lesson")
        XCTAssertEqual(first.kind, .focus)
        XCTAssertEqual(value.phase, .completed)
        XCTAssertEqual(try value.finish(at: epoch.addingTimeInterval(900)), first)
        var recovered = try FocusTimer(snapshot: JSONDecoder().decode(FocusSnapshot.self, from: JSONEncoder().encode(value.snapshot)))
        XCTAssertEqual(try recovered.finish(at: epoch.addingTimeInterval(1200)), first)
        XCTAssertThrowsError(try recovered.reset())
        XCTAssertThrowsError(try recovered.start(at: epoch.addingTimeInterval(1300)))
        XCTAssertThrowsError(try recovered.configure(subjectId: "other", minutes: 30))
        XCTAssertThrowsError(try recovered.acknowledgeCompletion(sessionID: "unrelated"))
        XCTAssertEqual(recovered.pendingSession, first)
        try recovered.acknowledgeCompletion(sessionID: first.id)
        XCTAssertNil(recovered.pendingSession)
        XCTAssertNil(try recovered.finish(at: epoch.addingTimeInterval(1500)))
        try recovered.acknowledgeCompletion(sessionID: first.id)
        try recovered.start(at: epoch.addingTimeInterval(2000))
        XCTAssertNotEqual(recovered.snapshot.sessionId, first.id)
        XCTAssertEqual(recovered.elapsedSeconds(at: epoch.addingTimeInterval(2003)), 3)
    }

    func testTargetCapsBackgroundTimeAndKeepsActualDeadline() throws {
        var value = try timer(minutes: 1)
        try value.start(at: epoch)
        XCTAssertEqual(value.elapsedSeconds(at: epoch.addingTimeInterval(600)), 60)
        XCTAssertEqual(value.remainingSeconds(at: epoch.addingTimeInterval(600)), 0)
        let session = try XCTUnwrap(value.finish(at: epoch.addingTimeInterval(600)))
        XCTAssertEqual(session.durationMinutes, 1)
        XCTAssertEqual(session.completedAt, StudyEngine.timestamp(epoch.addingTimeInterval(60)))
    }

    func testPauseAfterDeadlinePreservesDeadlineAcrossRelaunch() throws {
        var value = try timer(minutes: 1)
        try value.start(at: epoch)
        try value.pause(at: epoch.addingTimeInterval(300))
        XCTAssertThrowsError(try value.resume(at: epoch.addingTimeInterval(400)))
        var recovered = try FocusTimer(snapshot: value.snapshot)
        let session = try XCTUnwrap(recovered.finish(at: epoch.addingTimeInterval(500)))
        XCTAssertEqual(session.durationMinutes, 1)
        XCTAssertEqual(session.completedAt, StudyEngine.timestamp(epoch.addingTimeInterval(60)))
    }

    func testMultipleSegmentsReachTargetWithoutCountingPause() throws {
        var value = try timer(minutes: 1)
        try value.start(at: epoch)
        try value.pause(at: epoch.addingTimeInterval(20))
        try value.resume(at: epoch.addingTimeInterval(200))
        let session = try XCTUnwrap(value.finish(at: epoch.addingTimeInterval(600)))
        XCTAssertEqual(session.durationMinutes, 1)
        XCTAssertEqual(session.completedAt, StudyEngine.timestamp(epoch.addingTimeInterval(240)))
    }

    func testBackwardClockDoesNotCreateNegativeOrExtraElapsedTime() throws {
        var value = try timer()
        try value.start(at: epoch)
        XCTAssertEqual(value.elapsedSeconds(at: epoch.addingTimeInterval(-100)), 0)
        try value.pause(at: epoch.addingTimeInterval(-50))
        XCTAssertEqual(value.snapshot.accumulatedSeconds, 0)
        XCTAssertNil(try value.finish(at: epoch.addingTimeInterval(-10)))
    }

    func testEmptyTimerCannotEmitSessionOrResume() throws {
        var value = try timer()
        XCTAssertNil(try value.finish(at: epoch))
        XCTAssertThrowsError(try value.resume(at: epoch))
        try value.pause(at: epoch)
        XCTAssertEqual(value.phase, .idle)
        try value.start(at: epoch)
        XCTAssertNil(try value.finish(at: epoch))
        XCTAssertEqual(value.phase, .idle)
    }

    func testSecondStartCannotResetRunningTimestamp() throws {
        var value = try timer()
        try value.start(at: epoch)
        XCTAssertThrowsError(try value.start(at: epoch.addingTimeInterval(100)))
        XCTAssertEqual(value.elapsedSeconds(at: epoch.addingTimeInterval(120)), 120)
    }

    func testDurationAndContextBounds() throws {
        for minutes in [0, -1, Double.nan, .infinity, 1440.01] {
            XCTAssertThrowsError(try timer(minutes: minutes))
        }
        let max = try timer(minutes: 1440)
        XCTAssertEqual(max.snapshot.targetSeconds, 86_400)
        XCTAssertEqual(try timer(minutes: 2.0 / 60).snapshot.targetSeconds, 2)
        var value = FocusTimer()
        XCTAssertThrowsError(try value.configure(subjectId: "", lessonId: "lesson", minutes: 25))
        XCTAssertThrowsError(try value.configure(subjectId: " subject ", minutes: 25))
        XCTAssertThrowsError(try value.configure(subjectId: "subject\nother", minutes: 25))
        XCTAssertThrowsError(try value.configure(subjectId: String(repeating: "a", count: 201), minutes: 25))
    }

    func testInvalidSnapshotsAreRejectedBeforeUse() throws {
        let invalid = [
            FocusSnapshot(sessionId: ""), FocusSnapshot(targetSeconds: 0), FocusSnapshot(targetSeconds: .nan),
            FocusSnapshot(targetSeconds: 86_401), FocusSnapshot(accumulatedSeconds: -1),
            FocusSnapshot(targetSeconds: 60, accumulatedSeconds: 61), FocusSnapshot(lessonId: "unbound"),
            FocusSnapshot(accumulatedSeconds: 2, startedAt: epoch, completed: true),
            FocusSnapshot(targetSeconds: 60, accumulatedSeconds: 60, startedAt: epoch),
            FocusSnapshot(completed: true), FocusSnapshot(targetReachedAt: epoch),
            FocusSnapshot(startedAt: Date(timeIntervalSinceReferenceDate: .infinity)),
            FocusSnapshot(pendingSession: StudySession(durationMinutes: 1)),
        ]
        for snapshot in invalid { XCTAssertThrowsError(try FocusTimer(snapshot: snapshot)) }
        let corrupt = try JSONEncoder().encode(FocusSnapshot(accumulatedSeconds: -10))
        XCTAssertThrowsError(try JSONDecoder().decode(FocusTimer.self, from: corrupt))
    }

    func testTamperedPendingSessionCannotChangeLessonOrDuration() throws {
        var value = try timer()
        try value.start(at: epoch)
        _ = try value.finish(at: epoch.addingTimeInterval(30))
        var wrongLesson = value.snapshot
        wrongLesson.pendingSession?.lessonId = "other"
        XCTAssertThrowsError(try FocusTimer(snapshot: wrongLesson))
        var wrongDuration = value.snapshot
        wrongDuration.pendingSession?.durationMinutes = 50
        XCTAssertThrowsError(try FocusTimer(snapshot: wrongDuration))
        var wrongDate = value.snapshot
        wrongDate.pendingSession?.completedAt = "not a timestamp"
        XCTAssertThrowsError(try FocusTimer(snapshot: wrongDate))
    }
}
