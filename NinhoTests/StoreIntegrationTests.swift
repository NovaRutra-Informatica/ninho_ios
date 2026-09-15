import XCTest
import Foundation
import NinhoCore
@testable import Ninho

@MainActor final class StoreIntegrationTests: XCTestCase {
    private func fixture() -> AppState {
        AppState(settings: Settings(name: "Teste", sound: false),
                 programs: [StudyProgram(id: "test-program", name: "Curso de teste")],
                 subjects: [Subject(id: "test-subject", programId: "test-program", name: "Matéria de teste")],
                 courses: [Course(id: "test-course", subjectId: "test-subject", title: "Módulo de teste")],
                 lessons: [Lesson(id: "test-lesson", courseId: "test-course", subjectId: "test-subject", title: "Aula de teste", notes: "Notas preservadas")])
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-StoreTests-\(UUID().uuidString)")
    }

    private func currentFolder(_ root: URL) throws -> URL {
        let id = try JSONDecoder().decode(String.self, from: Data(contentsOf: root.appendingPathComponent("current.json")))
        XCTAssertNotNil(UUID(uuidString: id))
        return root.appendingPathComponent("collections").appendingPathComponent(id)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "The observable condition did not become true before the deadline")
    }

    private func thirtySecondsPaused() throws -> FocusTimer {
        let now = Date()
        var timer = FocusTimer()
        try timer.configure(subjectId: "test-subject", lessonId: "test-lesson", minutes: 25)
        try timer.start(at: now.addingTimeInterval(-30)); try timer.pause(at: now)
        return timer
    }

    func testWriteFailureBeforePendingCommitKeepsSessionForRealRetry() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let timer = try thirtySecondsPaused()
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        let store = NinhoStore(library: library)
        await store.start()
        XCTAssertTrue(store.loaded); XCTAssertNil(store.error)

        let generation = try JSONDecoder().decode(String.self, from: Data(contentsOf: root.appendingPathComponent("current.json")))
        XCTAssertNotNil(UUID(uuidString: generation))
        let focusFile = root.appendingPathComponent("collections").appendingPathComponent(generation).appendingPathComponent("focus.json")
        try FileManager.default.removeItem(at: focusFile)
        try FileManager.default.createDirectory(at: focusFile, withIntermediateDirectories: false)
        await store.focusAction("finish")
        XCTAssertNotNil(store.error)
        let pending = try XCTUnwrap(store.focus.pendingSession)
        XCTAssertEqual(pending.id, timer.snapshot.sessionId)
        XCTAssertTrue(store.state.sessions.isEmpty)
        await store.focusAction("reset")
        XCTAssertEqual(store.focus.pendingSession, pending)

        try FileManager.default.removeItem(at: focusFile)
        store.error = nil
        await store.focusAction("finish")
        XCTAssertNil(store.error)
        XCTAssertEqual(store.state.sessions, [pending])
        XCTAssertNil(store.focus.pendingSession)
        let reopened = try await StudyLibrary(root: root).load()
        XCTAssertEqual(reopened.sessions, [pending])
        XCTAssertEqual(reopened.lessons.first?.notes, "Notas preservadas")
        XCTAssertEqual(reopened.lessons.first?.status, .notStarted)
    }

    func testRelaunchAfterSessionCommitBeforeAcknowledgementDoesNotDuplicate() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        var timer = try thirtySecondsPaused()
        let session = try XCTUnwrap(timer.finish())
        // Simulate a crash after addSession, before acknowledging focus.json.
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        _ = try await library.apply(.addSession(session))
        let store = NinhoStore(library: StudyLibrary(root: root))
        await store.start()
        XCTAssertNil(store.error); XCTAssertTrue(store.loaded)
        XCTAssertEqual(store.state.sessions, [session])
        XCTAssertNil(store.focus.pendingSession)
        await store.focusAction("finish")
        XCTAssertEqual(store.state.sessions, [session])
        let reopened = StudyLibrary(root: root)
        let persisted = try await reopened.loadAuxiliary(FocusSnapshot.self, name: "focus.json")
        XCTAssertTrue(persisted?.completed == true)
        XCTAssertNil(persisted?.pendingSession)
    }

    func testRelaunchCommitsPendingSessionThatWasNotYetApplied() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        var timer = try thirtySecondsPaused()
        let session = try XCTUnwrap(timer.finish())
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        let store = NinhoStore(library: StudyLibrary(root: root))
        await store.start()
        XCTAssertNil(store.error)
        XCTAssertEqual(store.state.sessions, [session])
        XCTAssertEqual(store.focus.phase, .completed)
        XCTAssertNil(store.focus.pendingSession)
    }

    func testExpiredBackgroundTimerIsCappedAndAttributedOnceOnStartup() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let started = Date().addingTimeInterval(-120)
        var timer = FocusTimer()
        try timer.configure(subjectId: "test-subject", lessonId: "test-lesson", minutes: 1)
        try timer.start(at: started)
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        let store = NinhoStore(library: StudyLibrary(root: root))
        await store.start()
        XCTAssertNil(store.error)
        let session = try XCTUnwrap(store.state.sessions.first)
        XCTAssertEqual(session.durationMinutes, 1)
        XCTAssertEqual(session.completedAt, StudyEngine.timestamp(started.addingTimeInterval(60)))
        XCTAssertEqual(session.lessonId, "test-lesson")
        let next = NinhoStore(library: StudyLibrary(root: root))
        await next.start()
        XCTAssertEqual(next.state.sessions, [session])
        XCTAssertEqual(next.state.lessons.first?.status, .notStarted)
    }

    func testInvalidTimerDoesNotBlockLibraryAndOriginalSurvivesANewTimer() async throws {
        var invalid = FocusSnapshot(); invalid.targetSeconds = 0
        for original in [Data("{incomplete timer".utf8), try JSONEncoder().encode(invalid)] {
            let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let library = StudyLibrary(root: root)
            let initial = try await library.load(seed: fixture())
            let folder = try currentFolder(root), focusFile = folder.appendingPathComponent("focus.json")
            let stateBytes = try Data(contentsOf: folder.appendingPathComponent("state.json"))
            try original.write(to: focusFile)
            let store = NinhoStore(library: library)
            await store.start()
            XCTAssertTrue(store.loaded); XCTAssertEqual(store.state, initial)
            XCTAssertNil(store.error); XCTAssertNil(store.focusRecoveryIssue)
            XCTAssertTrue(store.focusRecoveryNotice?.contains("preservado") == true)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), stateBytes)
            let copies = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
            let copy = try XCTUnwrap(copies.first { $0.lastPathComponent.hasPrefix("focus-invalid-") })
            XCTAssertEqual(try Data(contentsOf: copy), original)
            await store.focusAction("start", subjectId: "test-subject", lessonId: "test-lesson", minutes: 1)
            XCTAssertTrue(store.focus.isRunning)
            XCTAssertEqual(try Data(contentsOf: copy), original)
            let saved = try await library.loadAuxiliary(FocusSnapshot.self, name: "focus.json")
            XCTAssertEqual(saved, store.focus.snapshot)
        }
    }

    func testFailedTimerPreservationBlocksOnlyFocusAndCanBeRetried() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let focusFile = try currentFolder(root).appendingPathComponent("focus.json")
        let original = Data("original invalid timer".utf8)
        try original.write(to: focusFile)
        let obstacle = root.appendingPathComponent("backups")
        try Data("recovery is temporarily unavailable".utf8).write(to: obstacle)
        let store = NinhoStore(library: library)
        await store.start()
        XCTAssertTrue(store.loaded); XCTAssertNotNil(store.focusRecoveryIssue)
        XCTAssertNotNil(store.focusRecoveryNotice)
        await store.focusAction("start", subjectId: "test-subject", lessonId: "test-lesson")
        XCTAssertFalse(store.focus.isRunning)
        XCTAssertEqual(try Data(contentsOf: focusFile), original)
        let saved = await store.perform(.updateLesson(id: "test-lesson", notes: "Estudos continuam disponíveis"))
        XCTAssertTrue(saved)
        XCTAssertEqual(store.state.lessons.first?.notes, "Estudos continuam disponíveis")
        try FileManager.default.removeItem(at: obstacle)
        await store.retryFocusRecovery()
        XCTAssertNil(store.focusRecoveryIssue)
        await store.focusAction("start", subjectId: "test-subject", lessonId: "test-lesson")
        XCTAssertTrue(store.focus.isRunning)
        let copies = try FileManager.default.contentsOfDirectory(at: obstacle, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copies.first)), original)
    }

    func testRootMonitorFinishesWithoutConstructingFocusViewAndDoesNotDuplicate() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let clock = StoreTestClock(Date().addingTimeInterval(-120))
        var timer = FocusTimer()
        try timer.configure(subjectId: "test-subject", lessonId: "test-lesson", minutes: 1)
        try timer.start(at: clock.date)
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        let store = NinhoStore(library: library, now: { clock.date })
        await store.start()
        XCTAssertTrue(store.focus.isRunning); XCTAssertTrue(store.state.sessions.isEmpty)
        let monitor = Task { await store.monitorFocus(every: .milliseconds(5)) }
        defer { monitor.cancel() }
        clock.date = Date()
        try await waitUntil { store.state.sessions.count == 1 && !store.busy }
        let session = try XCTUnwrap(store.state.sessions.first)
        XCTAssertEqual(session.id, timer.snapshot.sessionId)
        XCTAssertEqual(session.lessonId, "test-lesson"); XCTAssertEqual(session.durationMinutes, 1)
        XCTAssertEqual(session.completedAt, StudyEngine.timestamp(try XCTUnwrap(timer.snapshot.startedAt).addingTimeInterval(60)))
        await store.checkFocusCompletion(); await store.focusAction("finish")
        XCTAssertEqual(store.state.sessions, [session]); XCTAssertNil(store.focus.pendingSession)
        let reopened = try await StudyLibrary(root: root).load()
        XCTAssertEqual(reopened.sessions, [session]); XCTAssertEqual(reopened.lessons.first?.status, .notStarted)
    }

    func testMonitorRetriesACompletionSkippedWhileRealLibraryWriteIsBusy() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let clock = StoreTestClock(Date().addingTimeInterval(-120))
        var timer = FocusTimer()
        try timer.configure(subjectId: "test-subject", lessonId: "test-lesson", minutes: 1)
        try timer.start(at: clock.date)
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        let store = NinhoStore(library: library, now: { clock.date })
        await store.start()
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let blocker = Task { await library.occupyActorForStoreTest(entered: entered, release: release) }
        defer { release.signal(); blocker.cancel() }
        var actorOccupied = false
        try await waitUntil { if !actorOccupied { actorOccupied = entered.wait(timeout: .now()) == .success }; return actorOccupied }
        let write = Task { await store.perform(.updateLesson(id: "test-lesson", notes: "Gravado antes da conclusão")) }
        try await waitUntil { store.busy }
        clock.date = Date()
        await store.checkFocusCompletion()
        XCTAssertTrue(store.state.sessions.isEmpty)
        let monitor = Task { await store.monitorFocus(every: .milliseconds(5)) }
        defer { monitor.cancel() }
        release.signal()
        let saved = await write.value; XCTAssertTrue(saved)
        try await waitUntil { store.state.sessions.count == 1 && !store.busy }
        XCTAssertEqual(store.state.lessons.first?.notes, "Gravado antes da conclusão")
        XCTAssertEqual(store.state.sessions.first?.id, timer.snapshot.sessionId)
        XCTAssertEqual(store.state.sessions.first?.durationMinutes, 1)
        await store.checkFocusCompletion()
        XCTAssertEqual(store.state.sessions.count, 1)
    }

    func testAutomaticWriteFailureKeepsPendingAndRequiresAnExplicitRetry() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let clock = StoreTestClock(Date().addingTimeInterval(-120))
        var timer = FocusTimer()
        try timer.configure(subjectId: "test-subject", lessonId: "test-lesson", minutes: 1)
        try timer.start(at: clock.date)
        try await library.saveAuxiliary(timer.snapshot, name: "focus.json")
        let store = NinhoStore(library: library, now: { clock.date })
        await store.start()
        let focusFile = try currentFolder(root).appendingPathComponent("focus.json")
        try FileManager.default.removeItem(at: focusFile)
        try FileManager.default.createDirectory(at: focusFile, withIntermediateDirectories: false)
        clock.date = Date()
        await store.checkFocusCompletion()
        XCTAssertNotNil(store.error)
        let pending = try XCTUnwrap(store.focus.pendingSession)
        XCTAssertTrue(store.state.sessions.isEmpty)
        store.error = nil
        try FileManager.default.removeItem(at: focusFile)
        await store.checkFocusCompletion()
        XCTAssertNil(store.error); XCTAssertTrue(store.state.sessions.isEmpty)
        XCTAssertEqual(store.focus.pendingSession, pending)
        await store.focusAction("finish")
        XCTAssertNil(store.error); XCTAssertNil(store.focus.pendingSession)
        XCTAssertEqual(store.state.sessions, [pending])
    }
}

@MainActor private final class StoreTestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private extension StudyLibrary {
    // Hold the actor to exercise busy without replacing storage.
    func occupyActorForStoreTest(entered: DispatchSemaphore, release: DispatchSemaphore) {
        entered.signal()
        _ = release.wait(timeout: .now() + 5)
    }
}
