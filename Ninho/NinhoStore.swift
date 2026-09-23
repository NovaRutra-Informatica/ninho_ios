import Foundation
import SwiftUI
import NinhoCore

@MainActor final class NinhoStore: ObservableObject {
    @Published private(set) var state = AppState() { didSet { refreshOverview(); scheduleWidgetSnapshot(); scheduleCompactBackup() } }
    @Published private(set) var overview = StudyOverview()
    @Published private(set) var mentor = MentorReport()
    @Published private(set) var activityNotice = ""
    @Published private(set) var focusNotificationNotice = ""
    @Published private(set) var navigationTrackingEnabled = true
    @Published private(set) var widgetNotice = ""
    @Published private(set) var compactBackupNotice = ""
    @Published private(set) var cloudBackupNotice = ""
    @Published private(set) var cloudBackupEnabled = false
    @Published private(set) var compactBackupDate: String?
    @Published private(set) var cloudRecoveryNotice = ""
    private var backupCoordinator: CompactBackupCoordinator?
    private var backupTask: Task<Void, Never>?
    private var backupRequest = UUID()
    private var lastBackupUptime: TimeInterval = -.infinity
    private var lastBackupDay: String?
    private var backupsEnabled = true
    private let widgetPublisher = WidgetPublisher()
    private var widgetTask: Task<Void, Never>?
    private var widgetRevision = 0
    private var widgetsEnabled = true
    private var activity = LocalActivity()
    private var activityWritable = true
    private var activitySaving = false
    private var activityDirty = false
    private var appActive = true
    private var visibleRoutes: [(UUID, MentorRoute)] = []
    private var activeSince: Date?
    private var activeUptime: TimeInterval?
    private var lastInteractionUptime: TimeInterval = 0
    private var lastActivityFlush: TimeInterval = -.infinity
    private let focusNotifications = FocusNotifications()
    @Published private(set) var revision = 0
    @Published private(set) var overviewRevision = 0
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var focus = FocusTimer()
    @Published private(set) var notice = ""
    @Published private(set) var preferencesStatus = ""
    @Published private(set) var pendingSettings: Settings?
    private var preferenceQueue: [(id: UUID, command: StudyCommand)] = []
    private var preferenceDelay: Task<Void, Never>?
    private var preferencesSaving = false
    var hasPendingPreferences: Bool { !preferenceQueue.isEmpty }
    var displaySettings: Settings { pendingSettings ?? state.settings }
    @Published var focusRecoveryNotice: String?
    @Published private(set) var focusRecoveryIssue: String?
    private var library: StudyLibrary?
    private let sounds = StudySoundPlayer()
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var automaticFocusFailureID: String?
    private var overviewTask: Task<Void, Never>?
    private var overviewRequest = UUID()
    private var overviewRefreshAt = Date.distantFuture
    init(library: StudyLibrary? = nil, now: @escaping () -> Date = { Date() }, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.library = library; self.now = now; self.uptime = uptime; self.widgetsEnabled = library == nil; self.backupsEnabled = library == nil }
    var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting") }

    func refreshOverview() {
        revision += 1
        overviewTask?.cancel()
        guard appActive else { overviewTask = nil; return }
        let request = UUID(), snapshot = state, activitySnapshot = activity, date = now(), version = revision
        overviewRequest = request
        overviewTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let result = StudyEngine.overview(in: snapshot, at: date)
                return (result, StudyEngine.nextReviewRefresh(in: snapshot, after: date), try? AdaptiveMentor.analyze(snapshot, activity: activitySnapshot, overview: result, at: date))
            }
            let (result, deadline, analysis) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.overviewRequest == request else { return }
            self.overview = result; self.overviewRevision = version
            if let analysis { self.mentor = analysis }
            self.overviewRefreshAt = deadline; self.overviewTask = nil
        }
    }

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
            await prepareCompactBackups(library)
            state = try await library.load(seed: initialState())
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--with-test-material"), let source = Bundle.main.url(forResource: "test-material", withExtension: "pdf") {
                state = try await library.importMaterial(from: source, subjectId: "test-subject", lessonId: "test-lesson")
            }
            do {
                activity = try await library.loadAuxiliary(LocalActivity.self, name: "activity.json") ?? LocalActivity()
                try activity.validate(); activity.prune(at: now())
                navigationTrackingEnabled = activity.trackingEnabled
            } catch {
                activity = LocalActivity(); activityWritable = false
                activityNotice = "O histórico de uso não pôde ser aberto e foi preservado. Seus estudos continuam disponíveis. \(friendly(error))"
            }
            loaded = true
            startRouteInterval(countVisit: true); refreshOverview()
            await loadFocusIndependently()
            if focusRecoveryIssue == nil && focusNeedsCompletion {
                do { try await finishFocusInternal() }
                catch { automaticFocusFailureID = focus.snapshot.sessionId; self.error = friendly(error) }
            }
            if focusRecoveryIssue == nil && !isUITesting { focusNotificationNotice = await focusNotifications.update(focus, at: now()) }
            scheduleWidgetSnapshot()
            scheduleCompactBackup(immediate: true)
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

    func checkFocusCompletion() async {
        guard loaded, !busy, focusRecoveryIssue == nil, focusNeedsCompletion,
              automaticFocusFailureID != focus.snapshot.sessionId else { return }
        busy = true; defer { busy = false }
        do { try await finishFocusInternal() }
        catch { automaticFocusFailureID = focus.snapshot.sessionId; self.error = friendly(error) }
    }

    func monitorFocus(every interval: Duration = .seconds(1)) async {
        while !Task.isCancelled && appActive {
            await checkFocusCompletion()
            if loaded && overviewTask == nil && now() >= overviewRefreshAt { refreshOverview() }
            if loaded && uptime() - lastActivityFlush >= 30 {
                collectRouteInterval(); startRouteInterval(countVisit: false)
                let changed = activityDirty
                await persistActivity(); lastActivityFlush = uptime()
                if lastBackupDay != StudyEngine.localDate(now()) { scheduleCompactBackup(immediate: true) }
                if changed && visibleRoutes.last?.1 == .assistant { refreshOverview() }
            }
            do { try await Task.sleep(for: interval) }
            catch { return }
        }
    }
    private func initialState() throws -> AppState {
        if isUITesting {
            var seed = AppState(settings: Settings(name: "Teste"), programs: [.init(id: "test-program", name: "Curso de teste")], subjects: [.init(id: "test-subject", programId: "test-program", name: "Matéria de teste")], courses: [.init(id: "test-course", subjectId: "test-subject", title: "Módulo de teste")], lessons: [.init(id: "test-lesson", courseId: "test-course", subjectId: "test-subject", title: "Aula de teste")], cards: [.init(id: "test-card", subjectId: "test-subject", lessonId: "test-lesson", question: "Quanto é 2 + 2?", answer: "4")])
            let arguments = ProcessInfo.processInfo.arguments
            if !arguments.contains("--test-onboarding") {
                var profile = StudentProfile(); profile.name = "Teste"; profile.goal = "Aprender com dados sintéticos"
                profile.completedAt = StudyEngine.timestamp(Date()); profile.tutorialsSeen = TutorialPage.allCases.map(\.rawValue)
                seed.profile = profile
            }
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
        recordInteraction()
        guard let library, !busy else { return false }
        busy = true; defer { busy = false }
        do {
            error = nil
            let previous = state
            state = try await library.apply(command)
            if !state.settings.sound { sounds.stop() }
            if let cue = StudySoundPolicy.cue(after: command, previous: previous, updated: state) { sounds.play(cue, enabled: state.settings.sound && appActive) }
            return true
        } catch { self.error = friendly(error); return false }
    }
    func queueSettings(_ settings: Settings) {
        pendingSettings = settings
        preferenceQueue.removeAll { if case .updateSettings = $0.command { return true }; return false }
        queuePreference(.updateSettings(settings))
    }
    func queueProfile(_ profile: StudentProfile) {
        preferenceQueue.removeAll { if case .updateProfile = $0.command { return true }; return false }
        queuePreference(.updateProfile(profile))
    }
    private func queuePreference(_ command: StudyCommand) {
        recordInteraction()
        preferenceQueue.append((UUID(), command)); preferencesStatus = "Salvando automaticamente…"
        preferenceDelay?.cancel()
        preferenceDelay = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await self?.flushPreferences()
        }
    }
    func flushPreferences() async {
        while preferencesSaving || busy {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
        }
        guard let library else { return }
        preferencesSaving = true; busy = true
        defer { preferencesSaving = false; busy = false }
        while let first = preferenceQueue.first {
            do {
                state = try await library.apply(first.command)
                preferenceQueue.removeAll { $0.id == first.id }
                if !preferenceQueue.contains(where: { if case .updateSettings = $0.command { return true }; return false }) { pendingSettings = nil }
                if !state.settings.sound { sounds.stop() }
                preferencesStatus = preferenceQueue.isEmpty ? "Salvo neste iPhone" : "Salvando automaticamente…"
            } catch {
                preferencesStatus = "Não foi salvo: \(friendly(error))"
                return
            }
        }
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
        if count > 0 { sounds.play(.save, enabled: state.settings.sound && appActive) }
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
    func restoreBackup(_ url: URL, compact requestedCompact: Bool? = nil) async {
        guard let library, !busy else { return }
        busy = true; defer { busy = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            error = nil
            let compact: Bool
            if let requestedCompact { compact = requestedCompact }
            else { compact = try await library.isCompactBackup(url) }
            state = try await (compact ? library.restoreCompactBackup(from: url) : library.restoreBackup(from: url))
            loaded = true
            await focusNotifications.cancel()
            if compact, var restoredActivity = try await library.loadAuxiliary(LocalActivity.self, name: "activity.json") {
                try restoredActivity.validate(); restoredActivity.prune(at: now())
                activity = restoredActivity; navigationTrackingEnabled = activity.trackingEnabled
            } else { activity = LocalActivity(); activity.trackingEnabled = navigationTrackingEnabled }
            activityWritable = true; activityDirty = true
            activeSince = nil; activeUptime = nil; startRouteInterval(countVisit: true)
            await persistActivity(); refreshOverview()
            focus = FocusTimer()
            focusRecoveryIssue = nil; focusRecoveryNotice = nil; automaticFocusFailureID = nil
            try focus.configure(subjectId: "", minutes: Double(state.settings.focusMinutes))
            try await library.saveAuxiliary(focus.snapshot, name: "focus.json")
            notice = "Coleção restaurada. Uma cópia anterior foi preservada no aparelho."
            scheduleWidgetSnapshot()
            if let recovery = await library.takeRecoveryNotice() { notice = recovery }
            sounds.play(.complete, enabled: state.settings.sound && appActive)
        } catch { self.error = friendly(error) }
    }
    func focusAction(_ action: String, subjectId: String = "", lessonId: String = "", minutes: Double? = nil) async {
        recordInteraction()
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
            switch action {
            case "start": activity.focusStarted(id: focus.snapshot.sessionId, at: now())
            case "pause": activity.focusPaused(id: before.snapshot.sessionId)
            case "reset": activity.focusEnded(id: before.snapshot.sessionId, early: true, discarded: true)
            default: break
            }
            activityDirty = true; await persistActivity(); refreshOverview()
            scheduleWidgetSnapshot()
            if !isUITesting { focusNotificationNotice = await focusNotifications.update(focus, at: now()) }
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
        scheduleWidgetSnapshot()
        await focusNotifications.cancel(); focusNotificationNotice = ""
        activity.focusEnded(id: session.id, early: session.durationMinutes * 60 < focus.snapshot.targetSeconds * 0.8)
        activityDirty = true; await persistActivity(); refreshOverview()
        sounds.play(.focusDone, enabled: state.settings.sound && appActive)
        notice = "Tempo registrado na sua aula. Bom trabalho!"
    }
    func setAppActive(_ active: Bool) {
        guard active != appActive else { return }
        collectRouteInterval(); appActive = active
        if active { startRouteInterval(countVisit: true); refreshOverview(); scheduleWidgetSnapshot(); scheduleCompactBackup(immediate: true) }
        else { overviewTask?.cancel(); overviewTask = nil; sounds.stop() }
        Task { await persistActivity(); if !active { await flushPreferences(); scheduleCompactBackup(immediate: true) } }
    }

    private func prepareCompactBackups(_ library: StudyLibrary) async {
        guard backupsEnabled else { return }
        let root = await library.root
        let directory = isUITesting ? root.appendingPathComponent("CompactSnapshots") : root.deletingLastPathComponent().appendingPathComponent("NinhoSnapshots")
        let coordinator = CompactBackupCoordinator(localDirectory: directory, usesCloud: !isUITesting)
        backupCoordinator = coordinator; cloudBackupEnabled = await coordinator.cloudEnabled()
        do {
            if try await library.isPristine() {
                if let local = try await coordinator.localRecovery() {
                    _ = try await library.restoreCompactBackup(from: local.url, requirePristine: true)
                    compactBackupNotice = "Seu perfil e progresso foram recuperados da cópia compacta do aparelho."
                } else if !isUITesting {
                    do {
                        if let cloud = try await coordinator.recoveryFromCloud(requestDownload: false) {
                            _ = try await library.restoreCompactBackup(from: cloud.url, requirePristine: true)
                            cloudRecoveryNotice = "Perfil e progresso recuperados do iCloud. O envio de novas cópias continua desligado até você ativá-lo nos ajustes."
                        }
                    } catch { cloudRecoveryNotice = error.localizedDescription }
                }
            }
            if !isUITesting {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var excludedRoot = root, values = URLResourceValues(); values.isExcludedFromBackup = true
                try excludedRoot.setResourceValues(values)
            }
        } catch { compactBackupNotice = "Não foi possível preparar a recuperação automática: \(friendly(error)). A coleção existente foi preservada." }
    }
    private func scheduleCompactBackup(immediate: Bool = false) {
        guard loaded, backupsEnabled, let coordinator = backupCoordinator else { return }
        backupTask?.cancel()
        let request = UUID(); backupRequest = request
        backupTask = Task { [weak self] in
            if !immediate {
                let delay = max(2, 60 - ((self?.uptime() ?? 0) - (self?.lastBackupUptime ?? -.infinity)))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            let snapshot = state, activitySnapshot = activity, date = now()
            do {
                let result = try await coordinator.save(snapshot, activity: activitySnapshot, at: date)
                guard !Task.isCancelled, backupRequest == request else { return }
                compactBackupDate = result.local?.createdAt
                lastBackupUptime = uptime()
                lastBackupDay = StudyEngine.localDate(date)
                compactBackupNotice = "Backup compacto salvo automaticamente. São mantidos os últimos 7 dias."
                cloudBackupNotice = result.cloudMessage
            } catch is CancellationError { }
            catch {
                guard backupRequest == request else { return }
                compactBackupNotice = "Seus estudos foram salvos, mas a cópia compacta não pôde ser atualizada: \(friendly(error))"
            }
        }
    }
    func setCloudBackupEnabled(_ enabled: Bool) async {
        guard let coordinator = backupCoordinator else { return }
        do {
            try await coordinator.setCloudEnabled(enabled)
            cloudBackupEnabled = enabled
            cloudBackupNotice = enabled ? "Preparando uma cópia para o iCloud Drive…" : "Envio automático desligado. Cópias já existentes no iCloud não foram apagadas."
            if enabled { scheduleCompactBackup(immediate: true) }
        } catch { cloudBackupNotice = friendly(error) }
    }
    func exportCompactBackup() async -> URL? {
        await flushPreferences()
        guard !hasPendingPreferences, let coordinator = backupCoordinator else { return nil }
        do { return try await coordinator.export(state, activity: activity, at: now()) }
        catch { error = friendly(error); return nil }
    }
    func recoverCompactFromCloud() async {
        guard let coordinator = backupCoordinator, !busy else { return }
        do {
            guard let info = try await coordinator.recoveryFromCloud(requestDownload: true) else {
                cloudRecoveryNotice = "Ainda não localizei uma cópia disponível. O iCloud pode estar carregando a lista: confira a conta, aguarde e tente novamente, ou escolha um backup em Arquivos."; return
            }
            await restoreBackup(info.url, compact: true)
            if error == nil { cloudRecoveryNotice = "Seu perfil e progresso foram recuperados. Anexos e modelos continuam separados." }
        } catch { cloudRecoveryNotice = friendly(error) }
    }

    /// Widgets use persisted values only, never navigation time or an LLM.
    /// Unit/UI tests cannot write fictional data into the user's App Group.
    private func scheduleWidgetSnapshot() {
        guard loaded, widgetsEnabled, !isUITesting else { return }
        widgetTask?.cancel(); widgetRevision += 1
        let version = widgetRevision, snapshot = state, timer = focus, date = now()
        widgetTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { WidgetSummary.make(state: snapshot, focus: timer, at: date) }
            let summary = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.widgetRevision == version else { return }
            do {
                try await self.widgetPublisher.publish(summary, revision: version)
                if self.widgetRevision == version { self.widgetNotice = "" }
            } catch {
                if self.widgetRevision == version { self.widgetNotice = "O resumo dos widgets não pôde ser atualizado. Seus estudos estão salvos no aplicativo. Confirme o App Group na configuração de assinatura." }
            }
        }
    }

    func showRoute(_ route: MentorRoute, token: UUID) {
        guard !visibleRoutes.contains(where: { $0.0 == token }) else { return }
        collectRouteInterval(); visibleRoutes.append((token, route)); startRouteInterval(countVisit: true)
        Task { await persistActivity() }
    }
    func hideRoute(token: UUID) {
        let wasCurrent = visibleRoutes.last?.0 == token
        if wasCurrent { collectRouteInterval() }
        visibleRoutes.removeAll { $0.0 == token }
        if wasCurrent { startRouteInterval(countVisit: true); Task { await persistActivity() } }
    }
    private func startRouteInterval(countVisit: Bool) {
        guard loaded, appActive, let route = visibleRoutes.last?.1 else { return }
        let date = now(); activeSince = date; activeUptime = uptime()
        if countVisit { recordInteraction(); activity.visit(route, at: date); activityDirty = true }
    }
    private func collectRouteInterval() {
        defer { activeSince = nil; activeUptime = nil }
        guard loaded, appActive, let start = activeSince, let uptime = activeUptime, let route = visibleRoutes.last?.1 else { return }
        // Monotonic duration prevents a wall-clock change from becoming hours of fake usage.
        let end = min(self.uptime(), lastInteractionUptime + 60)
        guard end > uptime, activity.trackingEnabled else { return }
        activity.addForeground(route, from: start, seconds: max(0, end - uptime))
        activity.prune(at: now()); activityDirty = true
    }
    func recordInteraction() {
        guard appActive else { return }
        // First collect the old interval so an interaction after idle never backfills idle time.
        collectRouteInterval()
        lastInteractionUptime = uptime()
        if loaded, visibleRoutes.last != nil { activeSince = now(); activeUptime = uptime() }
    }
    func flushActivity() async {
        collectRouteInterval(); startRouteInterval(countVisit: false); await persistActivity()
    }
    func setNavigationTracking(_ enabled: Bool) async {
        collectRouteInterval(); activity.trackingEnabled = enabled; navigationTrackingEnabled = enabled
        activityDirty = true; startRouteInterval(countVisit: false); await persistActivity(); refreshOverview()
    }
    func clearLocalActivity() async {
        while activitySaving { do { try await Task.sleep(for: .milliseconds(10)) } catch { return } }
        let enabled = navigationTrackingEnabled
        activity = LocalActivity(); activity.trackingEnabled = enabled; activityWritable = true
        activityDirty = true; activeSince = nil; activeUptime = nil
        startRouteInterval(countVisit: false); await persistActivity(); refreshOverview()
    }
    private func persistActivity() async {
        guard let library, activityWritable else { return }
        while activitySaving { do { try await Task.sleep(for: .milliseconds(10)) } catch { return } }
        activitySaving = true; defer { activitySaving = false }
        while activityDirty {
            activityDirty = false
            do {
                try await library.saveAuxiliary(activity, name: "activity.json"); activityNotice = ""
                scheduleCompactBackup()
            }
            catch { activityDirty = true; activityNotice = "Não foi possível salvar o uso local. Seus registros de estudo estão separados: \(friendly(error))"; return }
        }
    }
    func enableFocusNotifications() async {
        guard !isUITesting else { return }
        do {
            if try await focusNotifications.requestPermission() {
                let message = await focusNotifications.update(focus, at: now())
                focusNotificationNotice = message.isEmpty ? "Avisos permitidos. O próximo foco terá uma notificação silenciosa ao terminar." : message
            } else { focusNotificationNotice = "Avisos não permitidos. Você pode autorizá-los nos Ajustes do iPhone. A contagem funciona sem notificações." }
        } catch { focusNotificationNotice = "Não foi possível ativar o aviso: \(friendly(error))" }
    }
    func prepareLocalPlan() async throws -> MentorReport {
        let snapshot = state, local = activity, date = now()
        let worker = Task.detached(priority: .userInitiated) { try AdaptiveMentor.analyze(snapshot, activity: local, at: date) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    func friendly(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return "Não foi possível concluir esta ação. \(error.localizedDescription)"
    }
}
