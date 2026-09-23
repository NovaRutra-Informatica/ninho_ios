import Foundation
import XCTest
@testable import NinhoCore

final class StudySoundsTests: XCTestCase {
    private func word(_ data: Data, _ offset: Int) -> UInt16 { UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8) }
    private func integer(_ data: Data, _ offset: Int) -> UInt32 { UInt32(word(data, offset)) | (UInt32(word(data, offset + 2)) << 16) }

    func testAllCuesAreShortValidMonoPCMWithFadedEdgesAndNoClipping() {
        for cue in SoundCue.allCases {
            let data = StudySounds.waveData(for: cue)
            XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
            XCTAssertEqual(Int(integer(data, 4)), data.count - 8)
            XCTAssertEqual(word(data, 20), 1)
            XCTAssertEqual(word(data, 22), 1)
            XCTAssertEqual(integer(data, 24), 22_050)
            XCTAssertEqual(word(data, 34), 16)
            XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
            XCTAssertEqual(Int(integer(data, 40)), data.count - 44)
            XCTAssertLessThanOrEqual(StudySounds.duration(for: cue), 0.5)
            let samples = stride(from: 44, to: data.count, by: 2).map { Int(Int16(bitPattern: word(data, $0))) }
            XCTAssertEqual(samples.first, 0)
            XCTAssertEqual(samples.last, 0)
            XCTAssertLessThan(samples.map(abs).max() ?? Int.max, 6_000)
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 1_000)
        }
    }

    func testCuesAreDeterministicAndDistinct() {
        let clips = SoundCue.allCases.map { StudySounds.waveData(for: $0) }
        XCTAssertEqual(Set(clips).count, SoundCue.allCases.count)
        XCTAssertEqual(StudySounds.waveData(for: .save), StudySounds.waveData(for: .save))
    }

    func testNavigationCueIsShorterAndQuieterThanSuccessSounds() {
        func peak(_ cue: SoundCue) -> Int {
            let data = StudySounds.waveData(for: cue)
            return stride(from: 44, to: data.count, by: 2)
                .map { abs(Int(Int16(bitPattern: word(data, $0)))) }.max() ?? 0
        }
        for cue in SoundCue.allCases where cue != .navigation {
            XCTAssertLessThan(StudySounds.duration(for: .navigation), StudySounds.duration(for: cue))
            XCTAssertLessThan(peak(.navigation), peak(cue))
        }
    }

    func testMutedOrUnchangedActionsHaveNoSuccessSound() {
        let previous = AppState()
        var changed = previous; changed.settings.name = "Outro nome"
        XCTAssertNil(StudySoundPolicy.cue(after: .updateSettings(changed.settings), previous: previous, updated: changed))
        var enabled = changed; enabled.settings.sound = true
        XCTAssertNil(StudySoundPolicy.cue(after: .updateSettings(enabled.settings), previous: enabled, updated: enabled))
        XCTAssertNil(StudySoundPolicy.cue(after: .updateSettings(enabled.settings), previous: changed, updated: enabled))
        var profileChanged = enabled; profileChanged.profile = StudentProfile()
        XCTAssertNil(StudySoundPolicy.cue(after: .updateProfile(profileChanged.profile!), previous: enabled, updated: profileChanged))
    }

    func testCompletionSoundOnlyOnTransitionIntoCompletedLesson() {
        var previous = AppState(settings: Settings(sound: true), lessons: [Lesson(id: "lesson", title: "Aula")])
        var updated = previous; updated.lessons[0].status = .done
        let done = StudyCommand.updateLesson(id: "lesson", status: .done)
        XCTAssertEqual(StudySoundPolicy.cue(after: done, previous: previous, updated: updated), .complete)
        previous = updated; updated.lessons[0].notes = "Nota nova"
        XCTAssertEqual(StudySoundPolicy.cue(after: done, previous: previous, updated: updated), .save)
    }

    func testReviewAndFocusHaveTheirOwnCuesWithoutDuplicatingReviewSessionSound() {
        let previous = AppState(settings: Settings(sound: true))
        var updated = previous
        updated.cards = [ReviewCard(id: "card")]
        XCTAssertEqual(StudySoundPolicy.cue(after: .reviewCard(id: "card", rating: .again), previous: previous, updated: updated), .review)
        let focus = StudySession(id: "focus", durationMinutes: 5, kind: .focus)
        updated.sessions = [focus]
        XCTAssertEqual(StudySoundPolicy.cue(after: .addSession(focus), previous: previous, updated: updated), .focusDone)
        let review = StudySession(id: "review", durationMinutes: 1, kind: .review)
        XCTAssertNil(StudySoundPolicy.cue(after: .addSession(review), previous: previous, updated: updated))
    }

    func testTaskAndExamCompletionProduceGentleCompletionCue() {
        let previous = AppState(settings: Settings(sound: true))
        var updated = previous
        let task = StudyTask(id: "task", title: "Estudar", completed: true)
        updated.tasks = [task]
        XCTAssertEqual(StudySoundPolicy.cue(after: .saveTask(task), previous: previous, updated: updated), .complete)
        let exam = Exam(id: "exam", title: "Prova", completed: true)
        updated.exams = [exam]
        XCTAssertEqual(StudySoundPolicy.cue(after: .saveExam(exam), previous: previous, updated: updated), .complete)
    }
}
