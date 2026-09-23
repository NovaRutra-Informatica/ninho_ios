import XCTest
@testable import NinhoCore

final class WelcomeJourneyTests: XCTestCase {
    func testTenQuestionScreensAreFollowedByASeparateReview() {
        XCTAssertEqual(WelcomeJourney.questionCount, 10)
        XCTAssertEqual(WelcomeJourney.reviewStep, 10)
    }

    func testResumeKeepsCurrentQuestionAndClampsInvalidLocalProgress() {
        var profile = StudentProfile(); profile.name = "Pessoa"; profile.goal = "Aprender álgebra"
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 8, profile: profile), 8)
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: -12, profile: profile), 0)
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 999, profile: profile), 10)
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 8, profile: nil), 0)
    }

    func testResumeCannotBypassMissingRequiredAnswersAfterRestore() {
        var profile = StudentProfile()
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 10, profile: profile), 0)
        profile.name = "Pessoa"
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 10, profile: profile), 1)
        profile.goal = "Aprender"; profile.availableDays = []
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 10, profile: profile), 6)
    }

    func testOptionalQuestionsCanBeSkippedAndAdvancingNeverCompletesProfile() {
        var profile = StudentProfile(); profile.name = "Pessoa"; profile.goal = "Aprender"
        for step in 0..<WelcomeJourney.questionCount {
            XCTAssertTrue(WelcomeJourney.canContinue(profile: profile, step: step))
            XCTAssertNil(profile.completedAt)
        }
        XCTAssertFalse(WelcomeJourney.canContinue(profile: profile, step: -1))
        XCTAssertFalse(WelcomeJourney.canContinue(profile: profile, step: 11))
        profile.completedAt = "2026-09-23T12:00:00Z"
        XCTAssertEqual(WelcomeJourney.resumeStep(saved: 8, profile: profile), 0)
    }
}
