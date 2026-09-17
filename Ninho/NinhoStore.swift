import Foundation
import SwiftUI
import NinhoCore

@MainActor final class NinhoStore: ObservableObject {
    @Published private(set) var state = AppState()
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var focus = FocusTimer()
    @Published private(set) var notice = ""
    @Published var focusRecoveryNotice: String?
    @Published private(set) var focusRecoveryIssue: String?
    private var library: StudyLibrary?
    private let sounds = StudySoundPlayer()
    private let now: () -> Date
    private var automaticFocusFailureID: String?
    init(library: StudyLibrary? = nil, now: @escaping () -> Date = { Date() }) { self.library = library; self.now = now }
    var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting") }

    func start() async {
        guard !loaded && !busy else { return }
        busy = true; defer { busy = false }
        do {
            error = nil
            if library == nil {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let profile = ProcessInfo.processInfo.environment["NINHO_TEST_PROFILE"] ?? "default"
                let safeProfile = profile.filter { $0.isLetter || $0.isNumber || $0 == "-" }
                let root = support.appendingPathComponent(isUITesting ? "NinhoUITests/\(safeProfile.isEmpty ? "default" : safeProfile)" : "Ninho")
                if isUITesting && ProcessInfo.processInfo.arguments.contains("--reset-test-data") && FileManager.default.fileExists(atPath: root.path) {
                    try FileManager.default.removeItem(at: root)
                }
                library = StudyLibrary(root: root)
            }
            guard let library else { return }
            state = try await library.load(seed: initialState())
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--with-test-material"), let source = Bundle.main.url(forResource: "test-material", withExtension: "pdf") {
                state = try await library.importMaterial(from: source, subjectId: "test-subject", lessonId: "test-lesson")
            }
            loaded = true
            await loadFocusIndependently()
            if focusRecoveryIssue == nil && focusNeedsCompletion {
                do { try await finishFocusInternal() }
                catch { automaticFocusFailureID = focus.snapshot.sessionId; self.error = friendly(error) }
            }
        } catch { self.error = friendly(error) }
    }

    /// A corrupt timer must not block studies or be overwritten before recovery.
    private func loadFocusIndependently() async {
        guard let library else { return }
        do {
            var restored = FocusTimer()
            if let snapshot = try await library.loadAuxiliary(FocusSnapshot.self, name: "focus.json") {
                restored = try FocusTimer(snapshot: snapshot)
                guard snapshot.subjectId.isEmpty || state.subjects.contains(where: { $0.id == snapshot.subjectId }),
                      snapshot.lessonId.isEmpty || state.lessons.contains(where: { $0.id == snapshot.lessonId && $0.subjectId == snapshot.subjectId }) else { throw FocusTimerError.invalidContext }
            } else { try restored.configure(subjectId: "", minutes: Double(state.settings.focusMinutes)) }
            focus = restored; focusRecoveryIssue = nil; focusRecoveryNotice = nil; automaticFocusFailureID = nil
        } catch {
            let originalError = error
            do {
                // Device/permission errors need a retry, not a fresh timer.
                guard originalError is DecodingError || originalError is FocusTimerError || originalError is LibraryError else { throw originalError }
                let preserved = try await library.preserveInvalidFocus()
                var fresh = FocusTimer()
                try fresh.configure(subjectId: "", minutes: Double(state.settings.focusMinutes))
                focus = fresh; focusRecoveryIssue = nil; automaticFocusFailureID = nil
                focusRecoveryNotice = "Sua biblioteca abriu normalmente. O cronômetro salvo estava inválido. Nenhum tempo novo foi registrado. " + (preserved.map { "O arquivo original foi preservado em backups/\($0)." } ?? "Não havia um arquivo de cronômetro para recuperar.")
            } catch {
                focusRecoveryIssue = "Seus estudos estão disponíveis. O cronômetro não pôde ser recuperado e foi bloqueado para preservar o registro original. \(friendly(error))"
                focusRecoveryNotice = focusRecoveryIssue
            }
        }
    }

    func retryFocusRecovery() async {
        guard loaded, !busy else { return }
        busy = true; defer { busy = false }
        await loadFocusIndependently()
    }

    private var focusNeedsCompletion: Bool {
        focus.pendingSession != nil || (!focus.snapshot.completed && focus.remainingSeconds(at: now()) <= 0)
    }

    /// Busy defers completion; write failures retain pendingSession for manual retry.
    func checkFocusCompletion() async {
        guard loaded, !busy, focusRecoveryIssue == nil, focusNeedsCompletion,
              automaticFocusFailureID != focus.snapshot.sessionId else { return }
        busy = true; defer { busy = false }
        do { try await finishFocusInternal() }
        catch { automaticFocusFailureID = focus.snapshot.sessionId; self.error = friendly(error) }
    }

    func monitorFocus(every interval: Duration = .seconds(1)) async {
        while !Task.isCancelled {
            await checkFocusCompletion()
            do { try await Task.sleep(for: interval) }
            catch { return }
        }
    }
    private func initialState() throws -> AppState {
        if isUITesting {
            var seed = AppState(settings: Settings(name: "Teste"), programs: [.init(id: "test-program", name: "Curso de teste")], subjects: [.init(id: "test-subject", programId: "test-program", name: "Matéria de teste")], courses: [.init(id: "test-course", subjectId: "test-subject", title: "Módulo de teste")], lessons: [.init(id: "test-lesson", courseId: "test-course", subjectId: "test-subject", title: "Aula de teste")], cards: [.init(id: "test-card", subjectId: "test-subject", lessonId: "test-lesson", question: "Quanto é 2 + 2?", answer: "4")])
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--test-review-due-seconds"), arguments.indices.contains(index + 1), let seconds = Double(arguments[index + 1]), seconds.isFinite, seconds > 0, seconds <= 60 {
                seed.cards[0].dueAt = StudyEngine.timestamp(Date().addingTimeInterval(seconds))
            }
            return seed
        }
        guard let url = Bundle.main.url(forResource: "seed-state", withExtension: "json") else { throw LibraryError.invalid("O catálogo inicial não foi incluído no aplicativo.") }
        var seed = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        seed.settings.sound = true
        let now = StudyEngine.timestamp(Date())
        for index in seed.cards.indices { seed.cards[index].createdAt = now; seed.cards[index].dueAt = now }
        return seed
    }
    @discardableResult func perform(_ command: StudyCommand) async -> Bool {
        guard let library, !busy else { return false }
        busy = true; defer { busy = false }
        do {
            error = nil
            let previous = state
            state = try await library.apply(command)
            if !state.settings.sound { sounds.stop() }
            if let cue = StudySoundPolicy.cue(after: command, previous: previous, updated: state) { sounds.play(cue, enabled: state.settings.sound) }
            return true
        } catch { self.error = friendly(error); return false }
    }
    func importFiles(_ urls: [URL], subjectId: String, lessonId: String) async {
        guard let library, !busy else { return }
        busy = true; defer { busy = false }
        var failed: [String] = [], recovered: [String] = [], count = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            do {
                state = try await library.importMaterial(from: url, subjectId: subjectId, lessonId: lessonId); count += 1
                if let message = await library.takeRecoveryNotice() { recovered.append(message) }
            }
            catch { failed.append("\(url.lastPathComponent): \(friendly(error))") }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        notice = (["\(count) arquivo(s) conferido(s) na biblioteca."] + recovered).joined(separator: "\n")
        if count > 0 { sounds.play(.save, enabled: state.settings.sound) }
        if !failed.isEmpty { error = failed.joined(separator: "\n") }
    }
    func materialURL(_ id: String) async throws -> URL {
        guard let library else { throw LibraryError.invalid("Abra a biblioteca primeiro.") }
        return try await library.materialURL(id: id)
    }
    func exportBackup() async -> URL? {
        guard let library, !busy else { return nil }
        busy = true; defer { busy = false }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-\(StudyEngine.localDate()).\(UUID().uuidString.prefix(6)).zip")
            try await library.exportBackup(to: url); return url
        } catch { self.error = friendly(error); return nil }
    }
    func restoreBackup(_ url: URL) async {
        guard let library, !busy else { return }
        busy = true; defer { busy = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            state = try await library.restoreBackup(from: url)
            loaded = true
            focus = FocusTimer()
            focusRecoveryIssue = nil; focusRecoveryNotice = nil; automaticFocusFailureID = nil
            try focus.configure(subjectId: "", minutes: Double(state.settings.focusMinutes))
            try await library.saveAuxiliary(focus.snapshot, name: "focus.json")
            notice = "Coleção restaurada. Uma cópia anterior foi preservada no aparelho."
            if let recovery = await library.takeRecoveryNotice() { notice = recovery }
            sounds.play(.complete, enabled: state.settings.sound)
        } catch { self.error = friendly(error) }
    }
    func focusAction(_ action: String, subjectId: String = "", lessonId: String = "", minutes: Double? = nil) async {
        guard let library, !busy else { return }
        guard focusRecoveryIssue == nil else { error = focusRecoveryIssue; return }
        busy = true; defer { busy = false }
        let before = focus
        do {
            error = nil
            switch action {
            case "start":
                guard subjectId.isEmpty || state.subjects.contains(where: { $0.id == subjectId }),
                      lessonId.isEmpty || state.lessons.contains(where: { $0.id == lessonId && $0.subjectId == subjectId }) else { throw FocusTimerError.invalidContext }
                var duration = minutes ?? Double(state.settings.focusMinutes)
                if isUITesting, let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--test-focus-seconds"), ProcessInfo.processInfo.arguments.indices.contains(i + 1), let seconds = Double(ProcessInfo.processInfo.arguments[i + 1]) { duration = max(1, min(60, seconds)) / 60 }
                try focus.configure(subjectId: subjectId, lessonId: lessonId, minutes: duration)
                try focus.start(at: now())
            case "pause": try focus.pause(at: now())
            case "resume": try focus.resume(at: now())
            case "reset": try focus.reset()
            case "finish": try await finishFocusInternal(); automaticFocusFailureID = nil; return
            default: return
            }
            try await library.saveAuxiliary(focus.snapshot, name: "focus.json")
        } catch { if action != "finish" { focus = before }; self.error = friendly(error) }
    }
    private func finishFocusInternal() async throws {
        guard let library, let session = try focus.finish(at: now()) else { return }
        try await library.saveAuxiliary(focus.snapshot, name: "focus.json")
        if !state.sessions.contains(where: { $0.id == session.id }) { state = try await library.apply(.addSession(session)) }
        var acknowledged = focus
        try acknowledged.acknowledgeCompletion(sessionID: session.id)
        try await library.saveAuxiliary(acknowledged.snapshot, name: "focus.json")
        focus = acknowledged
        sounds.play(.focusDone, enabled: state.settings.sound)
        notice = "Tempo registrado na sua aula. Bom trabalho!"
    }
    func friendly(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return "Não foi possível concluir esta ação. \(error.localizedDescription)"
    }
}
