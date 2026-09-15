import Foundation
import XCTest
@testable import NinhoCore

final class StudyEngineTests: XCTestCase {
    private let instant = "2026-09-14T12:00:00.000Z"
    private var now: Date { StudyEngine.parseTimestamp(instant)! }
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func fixture() -> AppState {
        AppState(
            programs: [StudyProgram(id: "senado", name: "Senado", track: .concurso), StudyProgram(id: "maua", name: "Mauá", track: .faculdade)],
            subjects: [Subject(id: "db", programId: "senado", name: "Banco de Dados", track: .concurso), Subject(id: "cc", programId: "maua", name: "Ciência da Computação", track: .faculdade)],
            courses: [Course(id: "db-module", subjectId: "db", title: "Fundamentos"), Course(id: "cc-module", subjectId: "cc", title: "Computação")],
            lessons: [Lesson(id: "db-00", courseId: "db-module", subjectId: "db", title: "Aula 00"), Lesson(id: "db-01", courseId: "db-module", subjectId: "db", title: "Aula 01", order: 1), Lesson(id: "cc-00", courseId: "cc-module", subjectId: "cc", title: "Aula 00")]
        )
    }
    private func card(_ id: String = "card", subject: String = "db", lesson: String? = "db-00") -> ReviewCard {
        ReviewCard(id: id, subjectId: subject, lessonId: lesson, question: "O que é uma chave primária?", answer: "Um identificador único de registro.", dueAt: instant, createdAt: instant)
    }
    private func apply(_ command: StudyCommand, _ state: AppState, at date: Date? = nil) throws -> AppState {
        try StudyEngine.apply(command, to: state, now: date ?? now, calendar: utc)
    }
    private func invalid(_ mutate: (inout AppState) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        var state = fixture(); mutate(&state)
        XCTAssertThrowsError(try StudyEngine.validate(state), file: file, line: line)
    }

    func testDefaultsAndEmptyStateHaveNoInventedStudyHistory() throws {
        let state = AppState()
        try StudyEngine.validate(state)
        XCTAssertEqual(state.settings, Settings(name: "Alessandro", dailyMinutes: 30, newCardsPerDay: 5, focusMinutes: 25, breakMinutes: 5))
        let overview = StudyEngine.overview(in: state, at: now, calendar: utc)
        XCTAssertEqual(overview.todayMinutes, 0)
        XCTAssertEqual(overview.streak, 0)
        XCTAssertTrue(state.lessons.isEmpty)
        XCTAssertTrue(overview.upcomingExams.isEmpty)
        XCTAssertTrue(overview.limits.contains { $0.contains("não mede domínio") })
    }

    func testJSONRoundTripUsesDesktopNamesAndExplicitNullableHistory() throws {
        var state = fixture(); state.cards = [card()]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)
        try StudyEngine.validate(decoded)
        XCTAssertEqual(decoded, state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["id"])
        XCTAssertEqual(json["version"] as? Int, 2)
        let lessons = try XCTUnwrap(json["lessons"] as? [[String: Any]])
        XCTAssertEqual(lessons[0]["status"] as? String, "not-started")
        XCTAssertTrue(lessons[0]["updatedAt"] is NSNull)
        let cards = try XCTUnwrap(json["cards"] as? [[String: Any]])
        XCTAssertTrue(cards[0]["lastReviewedAt"] is NSNull)
        XCTAssertEqual(cards[0]["createdAt"] as? String, instant)
        XCTAssertNil((json["settings"] as? [String: Any])?["id"])
    }

    func testDefaultCardUsesOneInstantForCreationAndDueDate() throws {
        var state = fixture()
        state.cards = [ReviewCard(subjectId: "db", question: "Pergunta", answer: "Resposta")]
        try StudyEngine.validate(state)
        XCTAssertEqual(state.cards[0].dueAt, state.cards[0].createdAt)
    }

    func testDesktopCatalogDecodesValidatesAndRoundTripsWithoutDroppingData() throws {
        let file = try XCTUnwrap(Bundle.module.url(forResource: "seed-state", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: file)
        let state = try JSONDecoder().decode(AppState.self, from: data)
        try StudyEngine.validate(state)
        XCTAssertEqual(state.programs.count, 2)
        XCTAssertEqual(state.subjects.count, 15)
        XCTAssertEqual(state.courses.count, 20)
        XCTAssertEqual(state.lessons.count, 271)
        XCTAssertEqual(state.cards.count, 71)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.lessons.allSatisfy { $0.status == .notStarted })
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: encoded), "All desktop JSON fields, nulls, text and numeric values must survive the Swift round trip.")
    }

    func testTimestampCalendarAndOffsetsAreStrict() {
        XCTAssertEqual(StudyEngine.parseTimestamp("2026-09-14T09:00:00-03:00"), now)
        for text in ["2026-02-30T12:00:00Z", "2026-09-14", "2026-09-14T25:00:00Z", "2026-09-14T12:60:00Z", "not-a-date"] {
            XCTAssertNil(StudyEngine.parseTimestamp(text), text)
        }
        var local = utc; local.timeZone = TimeZone(secondsFromGMT: -3 * 3600)!
        let early = StudyEngine.parseTimestamp("2026-09-14T01:00:00Z")!
        XCTAssertEqual(StudyEngine.localDate(early, calendar: local), "2026-09-13")
        XCTAssertEqual(StudyEngine.localDate(early, calendar: utc), "2026-09-14")
    }

    func testRejectsWrongVersionsDuplicateIDsAndMalformedSettings() {
        invalid { $0.version = 1 }
        invalid { $0.version = 3 }
        invalid { $0.subjects.append($0.subjects[0]) }
        invalid { $0.programs[0].id = "../outside" }
        invalid { $0.settings.name = "  " }
        invalid { $0.settings.dailyMinutes = 4 }
        invalid { $0.settings.newCardsPerDay = 201 }
        invalid { $0.settings.focusMinutes = 0 }
        invalid { $0.settings.breakMinutes = 61 }
        invalid { $0.programs[0].color = "red" }
    }

    func testRejectsOrphanAndCrossSubjectReferences() {
        invalid { $0.subjects[0].programId = "missing" }
        invalid { $0.subjects[0].track = .pessoal }
        invalid { $0.courses[0].subjectId = "missing" }
        invalid { $0.lessons[0].courseId = "cc-module" }
        invalid { $0.cards = [self.card(lesson: "cc-00")] }
        invalid { $0.cards = [self.card(lesson: "")] }
        invalid { $0.sessions = [StudySession(subjectId: "db", lessonId: "cc-00", durationMinutes: 5, completedAt: self.instant)] }
    }

    func testRejectsUnsafeURLsAndInvalidCalendarDates() {
        for url in ["javascript:alert(1)", "file:///private/a.pdf", "https://user:pass@example.com/a", "https://example.com/has space", "relative/page"] {
            invalid { $0.courses[0].url = url }
        }
        invalid { $0.exams = [Exam(title: "Prova", date: "2026-02-29")] }
        invalid { $0.exams = [Exam(title: "Prova", date: "2024-02-29", time: "24:00")] }
        invalid { $0.tasks = [StudyTask(title: "Revisar", date: "1899-12-31")] }
        invalid { $0.lessons[0].updatedAt = "2026-09-14" }
    }

    func testProgramsSubjectsAndModulesCreateEditAndValidateAsOneHierarchy() throws {
        let original = fixture()
        var state = try apply(.saveProgram(StudyProgram(id: "new", name: "Projeto", track: .pessoal)), original)
        state = try apply(.saveSubject(Subject(id: "new-subject", programId: "new", name: "Leitura", track: .pessoal)), state)
        state = try apply(.saveCourse(Course(id: "new-course", subjectId: "new-subject", title: "Textos")), state)
        state = try apply(.saveLesson(Lesson(id: "new-lesson", courseId: "new-course", subjectId: "new-subject", title: "Primeiro texto")), state)
        XCTAssertEqual(state.lessons.count, 4)
        XCTAssertEqual(original.lessons.count, 3)
        state = try apply(.saveProgram(StudyProgram(id: "new", name: "Faculdade", track: .faculdade)), state)
        XCTAssertEqual(state.subjects.last?.track, .faculdade)
        var module = state.courses.last!; module.title = "Textos revisados"; module.url = "https://example.com/a"
        state = try apply(.saveCourse(module), state)
        XCTAssertEqual(state.courses.last?.title, "Textos revisados")
        XCTAssertThrowsError(try apply(.saveSubject(Subject(programId: "missing", name: "Órfã")), state))
    }

    func testEditingLessonPreservesNotesProgressAndHistory() throws {
        var state = try apply(.updateLesson(id: "db-00", status: .inProgress, notes: "Anotações próprias"), fixture())
        let updated = state.lessons[0].updatedAt
        var edit = Lesson(id: "db-00", courseId: "db-module", subjectId: "db", title: "Novo nome", url: "https://example.com/00")
        edit.status = .done; edit.notes = "Tentativa de sobrescrita"
        state = try apply(.saveLesson(edit), state)
        XCTAssertEqual(state.lessons[0].title, "Novo nome")
        XCTAssertEqual(state.lessons[0].status, .inProgress)
        XCTAssertEqual(state.lessons[0].notes, "Anotações próprias")
        XCTAssertEqual(state.lessons[0].updatedAt, updated)
        state = try apply(.updateLesson(id: "db-00", notes: "Notas corrigidas"), state)
        XCTAssertEqual(state.lessons[0].status, .inProgress)
        XCTAssertThrowsError(try apply(.updateLesson(id: "missing", status: .done), state))
    }

    func testSavingCardCreatesFreshScheduleAndEditingPreservesReviewHistory() throws {
        var proposed = card(); proposed.flag = .outdated; proposed.repetitions = 999
        var state = try apply(.saveCard(proposed), fixture())
        XCTAssertEqual(state.cards[0].repetitions, 0)
        XCTAssertEqual(state.cards[0].flag, .none)
        state = try apply(.reviewCard(id: "card", rating: .again), state)
        state = try apply(.flagCard(id: "card", flag: .relearn), state)
        let history = state.cards[0]
        var edit = card(); edit.question = "Pergunta corrigida"; edit.lessonId = nil
        state = try apply(.saveCard(edit), state)
        XCTAssertEqual(state.cards[0].question, "Pergunta corrigida")
        XCTAssertNil(state.cards[0].lessonId)
        XCTAssertEqual(state.cards[0].dueAt, history.dueAt)
        XCTAssertEqual(state.cards[0].lastReviewedAt, history.lastReviewedAt)
        XCTAssertEqual(state.cards[0].lapses, 1)
        XCTAssertEqual(state.cards[0].flag, .relearn)
    }

    func testAllFourRatingsUseTransparentIntervalsAndPreserveFlags() throws {
        for (rating, days) in [(Rating.again, 10.0 / 1440), (.hard, 1), (.good, 1), (.easy, 4)] {
            var state = fixture(); state.cards = [card()]; state.cards[0].flag = .outdated
            state = try apply(.reviewCard(id: "card", rating: rating), state)
            let result = state.cards[0]
            XCTAssertEqual(result.intervalDays, days, accuracy: 0.0000001)
            XCTAssertEqual(StudyEngine.parseTimestamp(result.dueAt)!.timeIntervalSince(now), days * 86400, accuracy: 0.001)
            XCTAssertEqual(result.repetitions, 1)
            XCTAssertEqual(result.lapses, rating == .again ? 1 : 0)
            XCTAssertEqual(result.flag, .outdated)
            XCTAssertEqual(state.sessions[0].id, "review:first:card")
            XCTAssertEqual(state.sessions[0].durationMinutes, 0)
        }
    }

    func testGoodMultipliesIntervalEasyAddsGrowthAndCeilingsHold() throws {
        var state = fixture(); state.cards = [card()]
        state = try apply(.reviewCard(id: "card", rating: .easy), state)
        state = try apply(.reviewCard(id: "card", rating: .good), state, at: now.addingTimeInterval(86400))
        XCTAssertEqual(state.cards[0].intervalDays, 11)
        XCTAssertEqual(state.cards[0].ease, 2.65, accuracy: 0.0001)
        state.cards[0].intervalDays = 36500; state.cards[0].ease = 3.5
        state = try apply(.reviewCard(id: "card", rating: .easy), state, at: now.addingTimeInterval(86400))
        XCTAssertEqual(state.cards[0].intervalDays, 36500)
        XCTAssertEqual(state.cards[0].ease, 3.5)
        state.cards[0].ease = 1.3
        state = try apply(.reviewCard(id: "card", rating: .again), state, at: now.addingTimeInterval(86400))
        XCTAssertEqual(state.cards[0].ease, 1.3)
    }

    func testCalendarSchedulingPreservesLocalTimeThroughDaylightSaving() throws {
        var calendar = utc; calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeDST = StudyEngine.parseTimestamp("2026-03-07T17:00:00Z")!
        var state = fixture()
        state.cards = [ReviewCard(id: "card", subjectId: "db", question: "P", answer: "R", dueAt: StudyEngine.timestamp(beforeDST), createdAt: StudyEngine.timestamp(beforeDST))]
        let good = try StudyEngine.apply(.reviewCard(id: "card", rating: .good), to: state, now: beforeDST, calendar: calendar)
        XCTAssertEqual(StudyEngine.parseTimestamp(good.cards[0].dueAt)!.timeIntervalSince(beforeDST), 23 * 3600)
        let again = try StudyEngine.apply(.reviewCard(id: "card", rating: .again), to: state, now: beforeDST, calendar: calendar)
        XCTAssertEqual(StudyEngine.parseTimestamp(again.cards[0].dueAt)!.timeIntervalSince(beforeDST), 600)
    }

    func testSuspensionAndDeletionDoNotEraseReviewSessions() throws {
        var state = fixture(); state.cards = [card()]
        state = try apply(.reviewCard(id: "card", rating: .good), state)
        state = try apply(.suspendCard(id: "card", suspended: true), state)
        XCTAssertThrowsError(try apply(.reviewCard(id: "card", rating: .good), state))
        XCTAssertTrue(StudyEngine.dueCards(in: state, at: now.addingTimeInterval(86400), calendar: utc).isEmpty)
        state = try apply(.suspendCard(id: "card", suspended: false), state)
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now.addingTimeInterval(86400), calendar: utc).count, 1)
        state = try apply(.deleteCard(id: "card"), state)
        XCTAssertTrue(state.cards.isEmpty)
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertThrowsError(try apply(.deleteCard(id: "card"), state))
    }

    func testRejectsReviewBeforeCreationAndImpossibleNewCardHistory() throws {
        var state = fixture(); state.cards = [card()]
        XCTAssertThrowsError(try apply(.reviewCard(id: "card", rating: .good), state, at: now.addingTimeInterval(-1)))
        invalid { $0.cards = [self.card()]; $0.cards[0].lapses = 1 }
        invalid { $0.cards = [self.card()]; $0.cards[0].intervalDays = .nan }
        invalid { $0.cards = [self.card()]; $0.cards[0].dueAt = "2026-09-13T12:00:00Z" }
        invalid { $0.cards = [self.card()]; $0.cards[0].lastReviewedAt = "2026-09-13T12:00:00Z" }
    }

    func testDailyQuotaCountsFirstExposureDespiteRepeatedReviewAndCardDeletion() throws {
        var state = fixture(); state.settings.newCardsPerDay = 1; state.cards = [card("a"), card("b")]
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now, calendar: utc).map(\.id), ["a"])
        state = try apply(.reviewCard(id: "a", rating: .again), state)
        XCTAssertTrue(StudyEngine.dueCards(in: state, at: now, calendar: utc).isEmpty)
        let tenMinutes = now.addingTimeInterval(600)
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: tenMinutes, calendar: utc).map(\.id), ["a"])
        state = try apply(.reviewCard(id: "a", rating: .good), state, at: tenMinutes)
        XCTAssertTrue(StudyEngine.dueCards(in: state, at: tenMinutes, calendar: utc).isEmpty)
        state = try apply(.deleteCard(id: "a"), state)
        XCTAssertTrue(StudyEngine.dueCards(in: state, at: tenMinutes, calendar: utc).isEmpty)
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now.addingTimeInterval(86400), calendar: utc).map(\.id), ["b"])
    }

    func testQuotaFallbackForDesktopLegacyCardsAndSubjectFilterBeforeQuota() throws {
        var state = fixture(); state.settings.newCardsPerDay = 1
        state.cards = [card("a"), card("b", subject: "cc", lesson: "cc-00")]
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now, subjectId: "cc", calendar: utc).map(\.id), ["b"])
        state.cards[0].lastReviewedAt = instant; state.cards[0].repetitions = 1; state.cards[0].dueAt = StudyEngine.timestamp(now.addingTimeInterval(86400))
        XCTAssertTrue(StudyEngine.dueCards(in: state, at: now, subjectId: "cc", calendar: utc).isEmpty)
        state.settings.newCardsPerDay = 5
        XCTAssertTrue(StudyEngine.dueCards(in: state, at: now, limit: 0, calendar: utc).isEmpty)
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now, limit: 1, calendar: utc).count, 1)
    }

    func testDueReviewsPrecedeNewCardsAndNewLimitZeroStillAllowsReviews() throws {
        var state = fixture(); state.cards = [card("a-new"), card("z-review")]
        state.cards[1].lastReviewedAt = instant; state.cards[1].repetitions = 2
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now, calendar: utc).map(\.id), ["z-review", "a-new"])
        state.settings.newCardsPerDay = 0
        XCTAssertEqual(StudyEngine.dueCards(in: state, at: now, calendar: utc).map(\.id), ["z-review"])
    }

    func testExamsTasksAndSettingsCRUDRespectGeneralItemsAndDates() throws {
        var state = try apply(.saveExam(Exam(id: "exam", title: "Prova", date: "2026-09-15")), fixture())
        state = try apply(.saveTask(StudyTask(id: "task", title: "Revisar", date: "2026-09-14")), state)
        state = try apply(.saveTask(StudyTask(id: "task", title: "Revisão feita", date: "2026-09-14", completed: true)), state)
        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertTrue(state.tasks[0].completed)
        var settings = state.settings; settings.theme = .dark; settings.dailyMinutes = 60
        state = try apply(.updateSettings(settings), state)
        XCTAssertEqual(state.settings.theme, .dark)
        state = try apply(.deleteExam(id: "exam"), state)
        state = try apply(.deleteTask(id: "task"), state)
        XCTAssertTrue(state.exams.isEmpty && state.tasks.isEmpty)
        XCTAssertThrowsError(try apply(.deleteExam(id: "missing"), state))
        XCTAssertThrowsError(try apply(.deleteTask(id: "missing"), state))
    }

    func testSessionsRecordExactLessonTimeWithoutCompletingLessonAndRejectDuplicates() throws {
        var state = fixture()
        let session = StudySession(id: "session", subjectId: "db", lessonId: "db-00", durationMinutes: 1.25, completedAt: instant)
        state = try apply(.addSession(session), state)
        XCTAssertEqual(state.lessons[0].status, .notStarted)
        XCTAssertThrowsError(try apply(.addSession(session), state))
        XCTAssertThrowsError(try apply(.addSession(StudySession(id: "review:forged", completedAt: instant)), state))
        XCTAssertThrowsError(try apply(.addSession(StudySession(completedAt: StudyEngine.timestamp(now.addingTimeInterval(61)))), state))
        state = try apply(.addSession(StudySession(id: "zero", subjectId: "db", lessonId: "db-00", completedAt: instant)), state)
        state = try apply(.addSession(StudySession(id: "general", subjectId: "db", durationMinutes: 5, completedAt: instant)), state)
        let stats = StudyEngine.lessonStats(in: state)
        XCTAssertEqual(stats["db-00"], LessonStudyStats(durationMinutes: 1.25, sessionCount: 1))
        XCTAssertEqual(stats["db-01"], LessonStudyStats())
    }

    func testMaterialMetadataCreateMoveEditRemovePreservesPhysicalNameAndOriginalState() throws {
        let material = Material(id: "pdf", name: "Aula.pdf", storedName: "12345678-1234-1234-1234-123456789012.pdf", size: 42, subjectId: "db", lessonId: "db-00", createdAt: instant)
        let initial = fixture()
        var state = try apply(.addMaterial(material), initial)
        XCTAssertThrowsError(try apply(.addMaterial(material), state))
        state = try apply(.updateMaterial(id: "pdf", lessonId: "db-01", notes: "Minhas notas"), state)
        XCTAssertEqual(state.materials[0].storedName, material.storedName)
        XCTAssertEqual(state.materials[0].notes, "Minhas notas")
        XCTAssertThrowsError(try apply(.updateMaterial(id: "pdf", subjectId: "cc"), state))
        state = try apply(.updateMaterial(id: "pdf", subjectId: "cc", lessonId: "cc-00"), state)
        XCTAssertEqual(state.materials[0].lessonId, "cc-00")
        state = try apply(.updateMaterial(id: "pdf", subjectId: "", lessonId: ""), state)
        state = try apply(.removeMaterial(id: "pdf"), state)
        XCTAssertTrue(state.materials.isEmpty && initial.materials.isEmpty)
        XCTAssertThrowsError(try apply(.removeMaterial(id: "pdf"), state))
    }

    func testMaterialValidationRejectsTraversalDuplicateStorageAndSizeMismatch() {
        let valid = Material(id: "pdf", name: "Aula.pdf", storedName: "12345678-1234-1234-1234-123456789012.pdf", size: 42, createdAt: instant)
        invalid { $0.materials = [valid]; $0.materials[0].storedName = "../outside.pdf" }
        invalid { $0.materials = [valid]; $0.materials[0].type = "txt" }
        invalid { $0.materials = [valid]; $0.materials[0].size = 100 * 1024 * 1024 + 1 }
        invalid { $0.materials = [valid, valid]; $0.materials[1].id = "different" }
        invalid { $0.materials = [valid]; $0.materials[0].subjectId = "db"; $0.materials[0].lessonId = "cc-00" }
    }

    func testOverviewUsesActualDatesMinutesAndReviewActivityWithoutInventingTime() throws {
        var state = fixture(); state.cards = [card()]
        state = try apply(.reviewCard(id: "card", rating: .good), state)
        state = try apply(.addSession(StudySession(id: "yesterday", durationMinutes: 20, completedAt: StudyEngine.timestamp(now.addingTimeInterval(-86400)))), state)
        state = try apply(.addSession(StudySession(id: "today", subjectId: "db", lessonId: "db-00", durationMinutes: 12.5, completedAt: instant)), state)
        state.sessions.append(StudySession(id: "future", durationMinutes: 100, completedAt: StudyEngine.timestamp(now.addingTimeInterval(86400))))
        state.exams = [Exam(id: "past", title: "Anterior", date: "2026-09-13"), Exam(id: "next", title: "Próxima", date: "2026-09-15"), Exam(id: "done", title: "Feita", date: "2026-09-14", completed: true)]
        let overview = StudyEngine.overview(in: state, at: now, calendar: utc)
        XCTAssertEqual(overview.todayMinutes, 12.5)
        XCTAssertEqual(overview.weekMinutes, 32.5)
        XCTAssertEqual(overview.streak, 2)
        XCTAssertEqual(overview.upcomingExams.map(\.id), ["next"])
        XCTAssertEqual(overview.dailyGoalProgress, 12.5 / 30 * 100, accuracy: 0.001)
    }

    func testMentorColdStartHasUnknownEvidenceAndCoverageIsOnlyCards() {
        var state = fixture()
        var insight = StudyEngine.overview(in: state, at: now, calendar: utc).subjects.first { $0.subjectId == "db" }!
        XCTAssertEqual(insight.status, "Ainda sem evidência")
        XCTAssertEqual(insight.confidence, "sem evidência")
        XCTAssertNil(insight.coveragePercent)
        state.cards = [card()]
        insight = StudyEngine.overview(in: state, at: now, calendar: utc).subjects.first { $0.subjectId == "db" }!
        XCTAssertEqual(insight.coveragePercent, 0)
        XCTAssertEqual(insight.status, "Ainda sem evidência")
        XCTAssertTrue(insight.signals.contains { $0.contains("não mede domínio") })
    }

    func testMentorFlagsAgingAndExamUrgencyUseObservedEvidence() throws {
        var state = fixture(); state.cards = [card()]
        state = try apply(.reviewCard(id: "card", rating: .again), state)
        state.exams = [Exam(id: "exam", title: "Prova de BD", subjectId: "db", date: "2026-09-17")]
        let later = now.addingTimeInterval(2 * 86400)
        var insight = StudyEngine.overview(in: state, at: later, calendar: utc).subjects.first!
        XCTAssertEqual(insight.subjectId, "db")
        XCTAssertEqual(insight.status, "Revisão necessária")
        XCTAssertEqual(insight.daysToExam, 1)
        XCTAssertEqual(insight.priority, 4 + 2 + 40 + 8)
        XCTAssertEqual(insight.confidence, "baixa")
        XCTAssertTrue(insight.signals.contains { $0.contains("não prova esquecimento") })
        XCTAssertEqual(insight.outdatedCards, 0)
        state = try apply(.flagCard(id: "card", flag: .outdated), state)
        insight = StudyEngine.overview(in: state, at: later, calendar: utc).subjects.first!
        XCTAssertEqual(insight.status, "Conferir fonte")
        XCTAssertTrue(insight.signals.contains { $0.contains("não verificamos atualização automaticamente") })
    }

    func testStablePracticedCardsAreInDayButNotClaimedAsKnowledgeMastery() {
        var state = fixture()
        state.cards = (0..<5).map { index in
            var item = card("card-\(index)")
            item.lastReviewedAt = instant; item.repetitions = 3; item.intervalDays = 7
            item.dueAt = StudyEngine.timestamp(now.addingTimeInterval(7 * 86400)); return item
        }
        let overview = StudyEngine.overview(in: state, at: now, calendar: utc)
        let insight = overview.subjects.first { $0.subjectId == "db" }!
        XCTAssertEqual(insight.status, "Em dia")
        XCTAssertEqual(insight.confidence, "moderada")
        XCTAssertEqual(insight.coveragePercent, 100)
        XCTAssertTrue(overview.limits.contains { $0.contains("não mede domínio") })
    }
}
