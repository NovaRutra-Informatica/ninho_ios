import Foundation
import XCTest
@testable import NinhoCore

final class AdaptiveMentorTests: XCTestCase, @unchecked Sendable {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var now: Date { StudyEngine.parseTimestamp("2026-09-23T12:00:00Z")! }

    private func fixture(cardCount: Int, repetitions: Int, lapses: Int) -> AppState {
        AppState(subjects: [Subject(id: "math", name: "Álgebra")], cards: (0..<cardCount).map {
            ReviewCard(id: "card-\($0)", subjectId: "math", question: "Pergunta \($0)", answer: "Resposta", dueAt: "2027-01-01T12:00:00Z", lastReviewedAt: repetitions > 0 ? "2026-09-22T12:00:00Z" : nil, intervalDays: 3, repetitions: repetitions, lapses: lapses)
        })
    }

    func testNoHistoryCannotBecomeADifficultyOrHabitClaim() throws {
        let report = try AdaptiveMentor.analyze(AppState(), at: now, calendar: calendar)
        XCTAssertEqual(report.suggestions.map(\.id), ["begin"])
        XCTAssertTrue(report.suggestions[0].evidence.contains("Ainda não há evidência suficiente"))
        XCTAssertNil(AdaptiveMentor.smoothedDifficulty(again: 1, answers: 1))
        XCTAssertNil(AdaptiveMentor.smoothedDifficulty(again: 9, answers: 8))
    }

    func testDifficultyRequiresThreeCardsAndEightHistoricalAnswersAndUsesSmoothing() throws {
        let small = try AdaptiveMentor.analyze(fixture(cardCount: 2, repetitions: 20, lapses: 20), at: now)
        XCTAssertFalse(small.suggestions.contains { $0.id.hasPrefix("difficulty") })
        let fewAnswers = try AdaptiveMentor.analyze(fixture(cardCount: 3, repetitions: 2, lapses: 2), at: now)
        XCTAssertFalse(fewAnswers.suggestions.contains { $0.id.hasPrefix("difficulty") })
        let enough = try AdaptiveMentor.analyze(fixture(cardCount: 3, repetitions: 3, lapses: 2), at: now)
        let suggestion = try XCTUnwrap(enough.suggestions.first { $0.id == "difficulty-math" })
        XCTAssertEqual(suggestion.confidence, "Sinal inicial")
        XCTAssertTrue(suggestion.evidence.contains("6 avaliações"))
        XCTAssertTrue(suggestion.evidence.contains("históricas"))
        XCTAssertEqual(try XCTUnwrap(AdaptiveMentor.smoothedDifficulty(again: 8, answers: 8)), 0.75, accuracy: 0.001)
    }

    func testAbsenceOfRecordedPracticeIsNotCalledLackOfKnowledge() throws {
        var state = fixture(cardCount: 0, repetitions: 0, lapses: 0)
        state.lessons = [Lesson(id: "lesson", subjectId: "math", title: "Aula", status: .done)]
        let report = try AdaptiveMentor.analyze(state, at: now)
        let coverage = try XCTUnwrap(report.suggestions.first { $0.id == "coverage-math" })
        XCTAssertTrue(coverage.evidence.contains("não uma lacuna comprovada"))
    }

    func testHabitsNeedSeveralDaysAndComeFromStartsNotCompletionTimestamps() throws {
        var usage = LocalActivity()
        for index in 0..<6 { usage.focusStarted(id: "same-day-\(index)", at: now, calendar: calendar) }
        XCTAssertFalse(try AdaptiveMentor.analyze(AppState(), activity: usage, at: now, calendar: calendar).suggestions.contains { $0.id == "habit" })
        usage = LocalActivity()
        for day in 0..<3 {
            for index in 0..<3 {
                usage.focusStarted(id: "\(day)-\(index)", at: now.addingTimeInterval(Double(day - 2) * 86400), calendar: calendar)
            }
        }
        let habit = try XCTUnwrap(AdaptiveMentor.analyze(AppState(), activity: usage, at: now, calendar: calendar).suggestions.first { $0.id == "habit" })
        XCTAssertTrue(habit.detail.contains("12h e 15h"))
        XCTAssertTrue(habit.evidence.contains("não o seu horário de melhor desempenho"))
    }

    func testRepeatedPauseAndCompletionAreCountedOnceAndNotCalledDistraction() throws {
        var usage = LocalActivity()
        for day in 0..<3 {
            for index in 0..<2 {
                let id = "\(day)-\(index)"
                usage.focusStarted(id: id, at: now.addingTimeInterval(Double(day - 2) * 86400), calendar: calendar)
                usage.focusPaused(id: id); usage.focusPaused(id: id)
                usage.focusEnded(id: id, early: true); usage.focusEnded(id: id, early: true)
            }
        }
        XCTAssertEqual(usage.days.reduce(0) { $0 + $1.pausedSessions }, 6)
        XCTAssertEqual(usage.days.reduce(0) { $0 + $1.earlyFinishes }, 6)
        let breaks = try XCTUnwrap(AdaptiveMentor.analyze(AppState(), activity: usage, at: now, calendar: calendar).suggestions.first { $0.id == "breaks" })
        XCTAssertTrue(breaks.evidence.contains("não são tratadas como falta de atenção"))
    }

    func testForegroundUsageSplitsAtMidnightAndCannotBecomeStudyTime() throws {
        var usage = LocalActivity()
        let start = StudyEngine.parseTimestamp("2026-09-22T23:59:50Z")!
        usage.visit(.materials, at: start, calendar: calendar)
        usage.addForeground(.materials, from: start, seconds: 20, calendar: calendar)
        XCTAssertEqual(usage.days.count, 2)
        XCTAssertEqual(usage.days[0].routes["materials"]?.seconds, 10)
        XCTAssertEqual(usage.days[1].routes["materials"]?.seconds, 10)
        let state = AppState()
        let report = try AdaptiveMentor.analyze(state, activity: usage, at: now, calendar: calendar)
        XCTAssertEqual(report.activeMinutes, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertEqual(StudyEngine.overview(in: state, at: now).todayMinutes, 0)
        try usage.validate()
    }

    func testUsageRetentionCapsAtNinetyDaysRejectsExternalRoutesAndInvalidDurations() throws {
        var usage = LocalActivity()
        for day in 0..<120 { usage.visit(.today, at: now.addingTimeInterval(Double(day - 119) * 86400), calendar: calendar) }
        XCTAssertEqual(usage.days.count, 90)
        usage.addForeground(.today, from: now, seconds: -.infinity, calendar: calendar)
        XCTAssertEqual(usage.days.last?.routes["today"]?.seconds, 0)
        try usage.validate()
        usage.days[0].routes["other-app"] = RouteActivity()
        XCTAssertThrowsError(try usage.validate())
    }

    func testNavigationOptOutDoesNotCreateUsageOrEraseStudyRelatedEvents() throws {
        var usage = LocalActivity(); usage.trackingEnabled = false
        usage.visit(.studies, at: now); usage.addForeground(.studies, from: now, seconds: 30)
        XCTAssertTrue(usage.days.isEmpty)
        usage.focusStarted(id: "focus", at: now)
        XCTAssertEqual(usage.days.first?.focusStarts, 1)
        XCTAssertEqual(usage.days.first?.routes.count, 0)
        let decoded = try JSONDecoder().decode(LocalActivity.self, from: JSONEncoder().encode(usage))
        XCTAssertFalse(decoded.trackingEnabled)
    }

    func testPlanUsesCurrentCanonicalProfileAndDoesNotCompleteOnboarding() throws {
        var profile = StudentProfile(); profile.name = "Pessoa"; profile.goal = "Aprender álgebra"
        profile.availableDays = ["mon", "wed"]; profile.dailyMinutes = 40; profile.sessionMinutes = 15
        profile.preferences = "Exemplos curtos"; profile.plan = "Plano antigo"
        var state = AppState(profile: profile)
        let first = try AdaptiveMentor.analyze(state, at: now)
        XCTAssertTrue(first.plan.contains("2 bloco(s) de 15 minutos e um bloco de 10 minutos"))
        XCTAssertTrue(first.plan.contains("segunda, quarta")); XCTAssertTrue(first.plan.contains(profile.preferences))
        XCTAssertFalse(first.plan.contains("Plano antigo")); XCTAssertNil(state.profile?.completedAt)
        state.profile?.goal = "Aprender geometria"
        XCTAssertTrue(try AdaptiveMentor.analyze(state, at: now).plan.contains("Aprender geometria"))
    }

    func testActivityPersistsSeparatelyAndDoesNotPolluteTransferBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = StudyLibrary(root: root.appendingPathComponent("source"))
        _ = try await source.load()
        var usage = LocalActivity(); usage.visit(.assistant, at: now, calendar: calendar)
        try await source.saveAuxiliary(usage, name: "activity.json")
        let reopened = StudyLibrary(root: root.appendingPathComponent("source"))
        let saved = try await reopened.loadAuxiliary(LocalActivity.self, name: "activity.json")
        XCTAssertEqual(saved, usage)
        let archive = root.appendingPathComponent("backup.zip"); try await source.exportBackup(to: archive)
        let destination = StudyLibrary(root: root.appendingPathComponent("destination"))
        _ = try await destination.load(); let restored = try await destination.restoreBackup(from: archive)
        let transferred = try await destination.loadAuxiliary(LocalActivity.self, name: "activity.json")
        XCTAssertNil(transferred); XCTAssertTrue(restored.sessions.isEmpty)
    }

    func testCancelledAnalysisDoesNotPublishAPlan() async {
        let task = Task { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try AdaptiveMentor.analyze(AppState()); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        task.cancel(); let cancelled = await task.value; XCTAssertTrue(cancelled)
    }

    func testNotificationDeadlineSurvivesRelaunchAndMovesOnlyByExplicitPause() throws {
        var timer = FocusTimer(); try timer.configure(subjectId: "", minutes: 10); try timer.start(at: now)
        let restored = try FocusTimer(snapshot: JSONDecoder().decode(FocusSnapshot.self, from: JSONEncoder().encode(timer.snapshot)))
        XCTAssertEqual(restored.completionDate(at: now.addingTimeInterval(180)), now.addingTimeInterval(600))
        try timer.pause(at: now.addingTimeInterval(180)); XCTAssertNil(timer.completionDate(at: now.addingTimeInterval(200)))
        try timer.resume(at: now.addingTimeInterval(240))
        XCTAssertEqual(timer.completionDate(at: now.addingTimeInterval(250)), now.addingTimeInterval(660))
        XCTAssertNil(timer.completionDate(at: now.addingTimeInterval(900)))
    }
}
