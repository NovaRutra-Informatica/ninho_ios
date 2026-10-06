import XCTest
@testable import NinhoCore

final class CardLibraryQueryTests: XCTestCase {
    func testSearchKeepsOrderAndCombinesSubjectLessonAndQuestion() throws {
        let cards = [
            ReviewCard(id: "first", subjectId: "one", lessonId: "lesson", question: "Revisão de ÁLGEBRA"),
            ReviewCard(id: "second", subjectId: "one", lessonId: "other", question: "Revisão de álgebra"),
            ReviewCard(id: "third", subjectId: "two", lessonId: "lesson", question: "Revisão de álgebra"),
            ReviewCard(id: "fourth", subjectId: "one", lessonId: "lesson", question: "Banco de dados")
        ]
        XCTAssertEqual(try CardLibraryQuery.search(cards), cards)
        XCTAssertEqual(try CardLibraryQuery.search(cards, text: "álgebra").map(\.id), ["first", "second", "third"])
        XCTAssertEqual(try CardLibraryQuery.search(cards, subjectID: "one", lessonID: "lesson", text: "ÁLGEBRA").map(\.id), ["first"])
        XCTAssertTrue(try CardLibraryQuery.search(cards, text: "ausente").isEmpty)
        XCTAssertTrue(try CardLibraryQuery.search([]).isEmpty)
    }

    func testCancelledQueriesNeverPublishEmptyOrPartialResults() async throws {
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try CardLibraryQuery.search([ReviewCard(question: "Pergunta")], text: "Pergunta")
        }
        worker.cancel()
        do { _ = try await worker.value; XCTFail("Cancelled search must throw.") }
        catch is CancellationError { }
    }

    func testSearchFindsLastCardInLargeLibraryWithoutChangingCollection() throws {
        let cards = (0..<5_000).map { ReviewCard(id: "card-\($0)", question: "Pergunta \($0)") }
        XCTAssertEqual(try CardLibraryQuery.search(cards, text: "Pergunta 4999").map(\.id), ["card-4999"])
        XCTAssertEqual(cards.count, 5_000)
    }
}
