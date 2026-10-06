import Foundation
import XCTest
@testable import NinhoCore

final class StudyPerformanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_164_800)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func collection(_ count: Int) -> AppState {
        var state = AppState(programs: [StudyProgram(id: "program", name: "Carga", track: .concurso)],
                             subjects: [Subject(id: "subject", programId: "program", name: "Matéria", track: .concurso)])
        let created = StudyEngine.timestamp(now.addingTimeInterval(-90 * 86400))
        state.cards = (0..<count).map { index in
            let due = StudyEngine.timestamp(now.addingTimeInterval(Double(index % 29 - 28) * 86400))
            return ReviewCard(id: "card-\(index)", subjectId: "subject", question: "Pergunta \(index)", answer: "Resposta \(index)",
                              dueAt: due, lastReviewedAt: created, intervalDays: 7, repetitions: 3, lapses: index % 3,
                              createdAt: created)
        }
        state.sessions = (0..<count).map { index in
            StudySession(id: "session-\(index)", subjectId: "subject", durationMinutes: 25,
                         completedAt: StudyEngine.timestamp(now.addingTimeInterval(-Double(index) * 1800)))
        }
        return state
    }

    func testLargeCollectionsKeepDueCardsAndStudyTotals() throws {
        for count in [71, 1_000, 5_000] {
            let state = collection(count)
            try StudyEngine.validate(state)
            let cards = StudyEngine.dueCards(in: state, at: now, calendar: calendar)
            XCTAssertEqual(cards.count, count)
            XCTAssertEqual(Set(cards.map(\.id)).count, count)
            let overview = StudyEngine.overview(in: state, at: now, calendar: calendar)
            XCTAssertEqual(overview.reviewCards, count)
            XCTAssertEqual(overview.subjects.first?.studyMinutes, Double(count * 25))
            let widget = WidgetSummary.make(state: state, at: now, calendar: calendar)
            XCTAssertEqual(widget.moments.first?.dueReviews, count)
        }
    }

    func testConcurrentSummariesKeepIndependentDateParsers() async throws {
        let state = collection(71), date = now, calendar = calendar
        await withTaskGroup(of: [String].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let cards = StudyEngine.dueCards(in: state, at: date, calendar: calendar)
                    _ = WidgetSummary.make(state: state, at: date, calendar: calendar)
                    return cards.map(\.id)
                }
            }
            let expected = StudyEngine.dueCards(in: state, at: date, calendar: calendar).map(\.id)
            for await cards in group { XCTAssertEqual(cards, expected) }
        }
    }

    func testMeasuredWorkloads() throws {
        guard ProcessInfo.processInfo.environment["NINHO_PERFORMANCE"] == "1" else {
            throw XCTSkip("Run NINHO_PERFORMANCE=1 swift test -c release --filter StudyPerformanceTests for timings.")
        }
        for count in [71, 1_000, 5_000] {
            let state = collection(count)
            var distinct = state
            for index in distinct.cards.indices {
                distinct.cards[index].dueAt = StudyEngine.timestamp(now.addingTimeInterval(-Double(index + 1) * 60))
            }
            XCTAssertEqual(StudyEngine.dueCards(in: distinct, at: now, calendar: calendar).count, count)
            for (name, operation) in [
                ("due", { _ = StudyEngine.dueCards(in: state, at: self.now, calendar: self.calendar) }),
                ("due_distinct_timestamps", { _ = StudyEngine.dueCards(in: distinct, at: self.now, calendar: self.calendar) }),
                ("library_search", { _ = try CardLibraryQuery.search(state.cards, text: "Pergunta \(count - 1)") }),
                ("overview", { _ = StudyEngine.overview(in: state, at: self.now, calendar: self.calendar) }),
                ("widget", { _ = WidgetSummary.make(state: state, at: self.now, calendar: self.calendar) }),
                ("validate", { try StudyEngine.validate(state) })
            ] {
                var samples: [Double] = []
                for _ in 0..<5 {
                    let start = ContinuousClock.now
                    try operation()
                    let elapsed = start.duration(to: .now).components
                    samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                }
                samples.sort()
                let line = "NINHO_PERFORMANCE count=\(count) operation=\(name) median_ms=\(String(format: "%.3f", samples[2])) max_ms=\(String(format: "%.3f", samples[4]))\n"
                FileHandle.standardOutput.write(Data(line.utf8))
            }
        }
    }
}
