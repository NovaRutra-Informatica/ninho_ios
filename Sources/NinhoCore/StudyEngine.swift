import Foundation

public enum StudyError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}

public enum StudyEngine {
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func parseTimestamp(_ value: String) -> Date? {
        guard matches(value, #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#),
              calendarDay(String(value.prefix(10)), yearRange: 1...9999) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    public static func localDate(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw StudyError.invalid(message) }
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
    private static func validID(_ value: String, optional: Bool = false, maximum: Int = 200) -> Bool {
        (optional && value.isEmpty) || (value.utf16.count <= maximum && matches(value, #"^[A-Za-z0-9][A-Za-z0-9._:-]*$"#))
    }
    private static func label(_ value: String, _ maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= maximum
    }
    private static func webURL(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard value.utf16.count <= 4000, !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }
    private static func calendarDay(_ value: String, yearRange: ClosedRange<Int> = 1900...2200) -> Date? {
        guard matches(value, #"^\d{4}-\d{2}-\d{2}$"#) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, yearRange.contains(parts[0]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components), calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }
    private static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let first = calendarDay(from, yearRange: 1...9999), let last = calendarDay(to, yearRange: 1...9999) else { return 0 }
        return Int((last.timeIntervalSince(first) / 86400).rounded())
    }
    private static func unique<T: Identifiable>(_ items: [T], maximum: Int) throws where T.ID == String {
        try check(items.count <= maximum, "A coleção excede o limite permitido.")
        try check(Set(items.map(\.id)).count == items.count, "Há identificadores duplicados.")
    }

    public static func validate(_ state: AppState) throws {
        try check(state.version == 2, "Versão de dados incompatível. Importe uma coleção Ninho versão 2.")
        try state.profile?.validate()
        let settings = state.settings
        try check(label(settings.name, 100) && (5...720).contains(settings.dailyMinutes) && (0...200).contains(settings.newCardsPerDay) && (1...180).contains(settings.focusMinutes) && (1...60).contains(settings.breakMinutes), "Configurações fora dos limites permitidos.")
        try unique(state.programs, maximum: 500); try unique(state.subjects, maximum: 500)
        try unique(state.courses, maximum: 5000); try unique(state.lessons, maximum: 100000)
        try unique(state.cards, maximum: 100000); try unique(state.exams, maximum: 10000)
        try unique(state.materials, maximum: 10000); try unique(state.sessions, maximum: 500000)
        try unique(state.tasks, maximum: 100000)
        let programs = Dictionary(uniqueKeysWithValues: state.programs.map { ($0.id, $0) })
        let subjects = Set(state.subjects.map(\.id))
        let courses = Dictionary(uniqueKeysWithValues: state.courses.map { ($0.id, $0) })
        let lessons = Dictionary(uniqueKeysWithValues: state.lessons.map { ($0.id, $0) })
        var dates: [String: Date] = [:]
        func date(_ text: String) throws -> Date {
            if let cached = dates[text] { return cached }
            guard let parsed = parseTimestamp(text) else { throw StudyError.invalid("Data e horário inválidos.") }
            dates[text] = parsed; return parsed
        }
        func subject(_ id: String, optional: Bool = false) throws {
            try check(validID(id, optional: optional) && ((optional && id.isEmpty) || subjects.contains(id)), "A matéria vinculada não existe.")
        }
        func lesson(_ id: String?, subjectId: String) throws {
            if let id, !id.isEmpty { try check(validID(id) && lessons[id]?.subjectId == subjectId, "A aula não pertence à matéria selecionada.") }
        }
        for item in state.programs {
            try check(validID(item.id) && label(item.name, 150) && matches(item.color, #"^#[0-9a-fA-F]{6}$"#) && item.description.utf16.count <= 5000, "Curso inválido.")
        }
        for item in state.subjects {
            try check(validID(item.id) && validID(item.programId) && label(item.name, 150) && matches(item.color, #"^#[0-9a-fA-F]{6}$"#), "Matéria inválida.")
            try check(programs[item.programId]?.track == item.track, "O objetivo da matéria deve corresponder ao seu curso.")
        }
        for item in state.courses {
            try check(validID(item.id) && label(item.title, 500) && label(item.provider, 200) && webURL(item.url), "Módulo inválido.")
            try subject(item.subjectId)
        }
        for item in state.lessons {
            try check(validID(item.id) && validID(item.courseId) && label(item.title, 500) && item.description.utf16.count <= 20000 && item.notes.utf16.count <= 100000 && webURL(item.url) && (0...100000).contains(item.order), "Aula inválida.")
            try subject(item.subjectId)
            try check(courses[item.courseId]?.subjectId == item.subjectId, "A aula não pertence ao módulo selecionado.")
            if let updated = item.updatedAt { _ = try date(updated) }
        }
        for item in state.cards {
            try check(validID(item.id) && label(item.question, 10000) && label(item.answer, 50000) && item.source.utf16.count <= 5000 && webURL(item.sourceUrl), "Cartão inválido.")
            try subject(item.subjectId)
            if let lessonId = item.lessonId { try check(validID(lessonId), "Identificador de aula inválido.") }
            try lesson(item.lessonId, subjectId: item.subjectId)
            try check(item.intervalDays.isFinite && (0...36500).contains(item.intervalDays) && item.ease.isFinite && (1.3...3.5).contains(item.ease) && (0...1000000).contains(item.repetitions) && (0...1000000).contains(item.lapses), "Histórico do cartão inválido.")
            let created = try date(item.createdAt), due = try date(item.dueAt)
            try check(due >= created, "O agendamento do cartão é anterior à criação.")
            if let last = item.lastReviewedAt {
                let reviewed = try date(last)
                try check(reviewed >= created && due >= reviewed, "O agendamento do cartão é anterior ao seu histórico.")
            } else {
                try check(item.repetitions == 0 && item.lapses == 0 && item.intervalDays == 0, "Um cartão novo não pode ter histórico de revisão.")
            }
        }
        for item in state.exams {
            try check(validID(item.id) && label(item.title, 300) && calendarDay(item.date) != nil && matches(item.time, #"^(?:[01]\d|2[0-3]):[0-5]\d$|^$"#) && item.location.utf16.count <= 500 && item.notes.utf16.count <= 20000, "Prova inválida.")
            try subject(item.subjectId, optional: true)
        }
        for item in state.tasks {
            try check(validID(item.id) && label(item.title, 500) && calendarDay(item.date) != nil, "Tarefa inválida.")
            try subject(item.subjectId, optional: true)
        }
        let media = Set(["mp4", "webm", "mov", "mkv", "mp3", "wav", "ogg", "m4a", "aac", "flac"])
        var storedNames = Set<String>()
        for item in state.materials {
            try check(validID(item.id) && label(item.name, 500) && item.notes.utf16.count <= 100000 && matches(item.storedName, #"(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|png|jpg|jpeg|webp|txt|md|docx|pptx|xlsx|mp4|webm|mov|mkv|mp3|wav|ogg|m4a|aac|flac)$"#), "Metadados do arquivo inválidos.")
            try check(item.storedName.split(separator: ".").last?.lowercased() == item.type && item.size >= 0 && item.size <= (media.contains(item.type) ? 2 * 1024 * 1024 * 1024 : 100 * 1024 * 1024), "O tamanho ou tipo do arquivo não corresponde à extensão.")
            try check(storedNames.insert(item.storedName.lowercased()).inserted, "Há arquivos internos duplicados.")
            try subject(item.subjectId, optional: true)
            try check(validID(item.lessonId, optional: true), "Identificador de aula inválido.")
            try lesson(item.lessonId, subjectId: item.subjectId); _ = try date(item.createdAt)
        }
        for item in state.sessions {
            try check(validID(item.id, maximum: 300) && item.durationMinutes.isFinite && (0...1440).contains(item.durationMinutes), "Sessão inválida.")
            try subject(item.subjectId, optional: true)
            try check(validID(item.lessonId, optional: true), "Identificador de aula inválido.")
            try lesson(item.lessonId, subjectId: item.subjectId); _ = try date(item.completedAt)
        }
    }

    private static func index<T: Identifiable>(_ id: String, in items: [T]) throws -> Int where T.ID == String {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw StudyError.invalid("Este item não existe mais.") }
        return index
    }
    private static func save<T: Identifiable>(_ item: T, into items: inout [T]) where T.ID == String {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.append(item) }
    }

    public static func apply(_ command: StudyCommand, to state: AppState, now: Date = Date(), calendar: Calendar = .current) throws -> AppState {
        try validate(state)
        try check(now.timeIntervalSince1970.isFinite, "Relógio inválido.")
        var next = state
        switch command {
        case .updateSettings(let settings):
            next.settings = settings
            if next.profile != nil {
                next.profile?.name = settings.name; next.profile?.dailyMinutes = settings.dailyMinutes
                next.profile?.sessionMinutes = settings.focusMinutes
                if next.profile?.answers != state.profile?.answers { next.profile?.revision += 1; next.profile?.planStatus = "none" }
            }
        case .updateProfile(var profile):
            // Tutorial progress belongs to its dedicated commands, not a possibly stale editor.
            profile.tutorialsSeen = state.profile?.tutorialsSeen ?? profile.tutorialsSeen
            profile.updatedAt = timestamp(now)
            if profile.answers != state.profile?.answers { profile.revision = (state.profile?.revision ?? 0) + 1; profile.planStatus = "none" }
            else { profile.revision = state.profile?.revision ?? profile.revision }
            next.profile = profile
            if !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.settings.name = profile.name }
            next.settings.dailyMinutes = min(720, max(5, profile.dailyMinutes))
            next.settings.focusMinutes = min(180, profile.sessionMinutes)
        case .completeTutorial(let page):
            var pages = next.profile?.tutorialsSeen ?? []
            if !pages.contains(page.rawValue) { pages.append(page.rawValue) }
            next.profile?.tutorialsSeen = pages
        case .resetTutorials: next.profile?.tutorialsSeen = []
        case .saveProgram(let program):
            save(program, into: &next.programs)
            for i in next.subjects.indices where next.subjects[i].programId == program.id { next.subjects[i].track = program.track }
        case .saveSubject(let subject): save(subject, into: &next.subjects)
        case .saveCourse(let course): save(course, into: &next.courses)
        case .saveLesson(var lesson):
            if let old = state.lessons.first(where: { $0.id == lesson.id }) {
                lesson.status = old.status; lesson.notes = old.notes; lesson.updatedAt = old.updatedAt
            } else { lesson.status = .notStarted; lesson.notes = ""; lesson.updatedAt = nil }
            save(lesson, into: &next.lessons)
        case .updateLesson(let id, let status, let notes):
            let i = try index(id, in: next.lessons)
            if let status { next.lessons[i].status = status }
            if let notes { next.lessons[i].notes = notes }
            next.lessons[i].updatedAt = timestamp(now)
        case .saveCard(let content):
            var card = state.cards.first(where: { $0.id == content.id }) ?? ReviewCard(id: content.id, dueAt: timestamp(now), createdAt: timestamp(now))
            card.subjectId = content.subjectId; card.lessonId = content.lessonId
            card.question = content.question; card.answer = content.answer; card.source = content.source; card.sourceUrl = content.sourceUrl
            save(card, into: &next.cards)
        case .reviewCard(let id, let rating):
            let i = try index(id, in: next.cards)
            var card = next.cards[i]
            try check(!card.suspended, "Reative o cartão antes de revisar.")
            try check(parseTimestamp(card.createdAt)! <= now && (card.lastReviewedAt.flatMap(parseTimestamp) ?? .distantPast) <= now, "A revisão não pode voltar no tempo.")
            let sessionId = card.lastReviewedAt == nil ? "review:first:\(card.id)" : "review:\(card.id):\(Int64((now.timeIntervalSince1970 * 1000).rounded())):\(card.repetitions)"
            var interval: Double
            switch rating {
            case .again: interval = 10.0 / 1440; card.ease = max(1.3, card.ease - 0.2)
            case .hard: interval = 1; card.ease = max(1.3, card.ease - 0.15)
            case .good: interval = card.intervalDays < 1 ? 1 : max(1, (card.intervalDays * card.ease).rounded())
            case .easy:
                interval = card.intervalDays < 1 ? 4 : max(4, (card.intervalDays * card.ease * 1.3).rounded())
                card.ease = min(3.5, card.ease + 0.15)
            }
            interval = min(36500, interval)
            guard let due = rating == .again ? now.addingTimeInterval(600) : calendar.date(byAdding: .day, value: Int(interval), to: now) else { throw StudyError.invalid("Não foi possível agendar a revisão.") }
            card.intervalDays = interval; card.dueAt = timestamp(due); card.lastReviewedAt = timestamp(now)
            card.repetitions += 1; card.lapses += rating == .again ? 1 : 0
            next.cards[i] = card
            next.sessions.append(StudySession(id: sessionId, subjectId: card.subjectId, lessonId: card.lessonId ?? "", durationMinutes: 0, completedAt: timestamp(now), kind: .review))
        case .flagCard(let id, let flag): next.cards[try index(id, in: next.cards)].flag = flag
        case .suspendCard(let id, let suspended): next.cards[try index(id, in: next.cards)].suspended = suspended
        case .deleteCard(let id): next.cards.remove(at: try index(id, in: next.cards))
        case .saveExam(let exam): save(exam, into: &next.exams)
        case .deleteExam(let id): next.exams.remove(at: try index(id, in: next.exams))
        case .saveTask(let task): save(task, into: &next.tasks)
        case .deleteTask(let id): next.tasks.remove(at: try index(id, in: next.tasks))
        case .addSession(let session):
            try check(!state.sessions.contains(where: { $0.id == session.id }), "Esta sessão já foi registrada.")
            try check(!session.id.hasPrefix("review:"), "Identificador reservado para revisões.")
            try check((parseTimestamp(session.completedAt) ?? .distantFuture) <= now.addingTimeInterval(60), "A sessão não pode terminar no futuro.")
            next.sessions.append(session)
        case .addMaterial(let material):
            try check(!state.materials.contains(where: { $0.id == material.id }), "Este arquivo já foi registrado.")
            next.materials.append(material)
        case .updateMaterial(let id, let subjectId, let lessonId, let notes):
            let i = try index(id, in: next.materials)
            if let subjectId { next.materials[i].subjectId = subjectId }
            if let lessonId { next.materials[i].lessonId = lessonId }
            if let notes { next.materials[i].notes = notes }
        case .removeMaterial(let id): next.materials.remove(at: try index(id, in: next.materials))
        }
        try validate(next)
        return next
    }

    public static func dueCards(in state: AppState, at now: Date = Date(), limit: Int? = nil, subjectId: String? = nil, calendar: Calendar = .current) -> [ReviewCard] {
        let today = localDate(now, calendar: calendar)
        let firstReviews = state.sessions.filter { $0.kind == .review && $0.id.hasPrefix("review:first:") }
        let tracked = Set(firstReviews.map { String($0.id.dropFirst("review:first:".count)) })
        let used = firstReviews.filter { parseTimestamp($0.completedAt).map { localDate($0, calendar: calendar) == today } ?? false }.count
        let legacy = state.cards.filter { card in
            !tracked.contains(card.id) && card.repetitions == 1 && (card.lastReviewedAt.flatMap(parseTimestamp).map { localDate($0, calendar: calendar) == today } ?? false)
        }.count
        let available = max(0, state.settings.newCardsPerDay - used - legacy)
        let candidates = state.cards.filter { !$0.suspended && (subjectId == nil || subjectId == $0.subjectId) && (parseTimestamp($0.dueAt) ?? .distantFuture) <= now }
        let reviews = candidates.filter { $0.lastReviewedAt != nil }.sorted {
            let first = parseTimestamp($0.dueAt) ?? .distantFuture, second = parseTimestamp($1.dueAt) ?? .distantFuture
            if first != second { return first < second }
            if $0.lapses != $1.lapses { return $0.lapses > $1.lapses }
            return $0.id < $1.id
        }
        let fresh = candidates.filter { $0.lastReviewedAt == nil }.sorted {
            let first = parseTimestamp($0.createdAt) ?? .distantFuture, second = parseTimestamp($1.createdAt) ?? .distantFuture
            return first == second ? $0.id < $1.id : first < second
        }
        let result = reviews + Array(fresh.prefix(available))
        return limit.map { Array(result.prefix(max(0, $0))) } ?? result
    }

    public static func lessonStats(in state: AppState) -> [String: LessonStudyStats] {
        var result = Dictionary(state.lessons.map { ($0.id, LessonStudyStats()) }, uniquingKeysWith: { first, _ in first })
        let subjects = Dictionary(state.lessons.map { ($0.id, $0.subjectId) }, uniquingKeysWith: { first, _ in first })
        for session in state.sessions where session.durationMinutes > 0 && subjects[session.lessonId] == session.subjectId {
            result[session.lessonId, default: LessonStudyStats()].durationMinutes += session.durationMinutes
            result[session.lessonId, default: LessonStudyStats()].sessionCount += 1
        }
        return result
    }

    public static func nextReviewRefresh(in state: AppState, after now: Date, subjectId: String? = nil, calendar: Calendar = .current) -> Date {
        var next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        for card in state.cards where !card.suspended && (subjectId == nil || card.subjectId == subjectId) {
            if let due = parseTimestamp(card.dueAt), due > now, due < next { next = due }
        }
        return next
    }

    public static func overview(in state: AppState, at now: Date = Date(), calendar: Calendar = .current) -> StudyOverview {
        let today = localDate(now, calendar: calendar), due = dueCards(in: state, at: now, calendar: calendar)
        var minutes: [String: Double] = [:], subjectMinutes: [String: Double] = [:], active = Set<String>()
        for session in state.sessions {
            guard let completed = parseTimestamp(session.completedAt), completed <= now else { continue }
            let day = localDate(completed, calendar: calendar)
            minutes[day, default: 0] += session.durationMinutes
            subjectMinutes[session.subjectId, default: 0] += session.durationMinutes
            if StudyStreak.countsAsStudy(session) { active.insert(day) }
        }
        let streak = StudyStreak.current(activeDays: active, at: now, calendar: calendar)
        let weekMinutes = (0..<7).reduce(0.0) { sum, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return sum }
            return sum + (minutes[localDate(date, calendar: calendar)] ?? 0)
        }
        let exams = state.exams.filter { !$0.completed && $0.date >= today }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.id < $1.id
        }
        let cardsBySubject = Dictionary(grouping: state.cards, by: \.subjectId)
        let lessonsBySubject = Dictionary(grouping: state.lessons, by: \.subjectId)
        let unsortedInsights: [SubjectInsight] = state.subjects.map { subject -> SubjectInsight in
            let cards = cardsBySubject[subject.id] ?? []
            let practiced = cards.filter { $0.lastReviewedAt != nil }
            let due = practiced.filter { !$0.suspended && (parseTimestamp($0.dueAt) ?? .distantFuture) <= now }
            let outdated = cards.filter { $0.flag == .outdated }.count, relearn = cards.filter { $0.flag == .relearn }.count
            let lessons = lessonsBySubject[subject.id] ?? [], done = lessons.filter { $0.status == .done }.count
            let studyMinutes = subjectMinutes[subject.id] ?? 0
            let stable = practiced.filter { $0.repetitions >= 3 && $0.intervalDays >= 7 }.count
            let coverage: Double? = cards.isEmpty ? nil : (Double(practiced.count) / Double(cards.count) * 100).rounded()
            let exam = exams.first { $0.subjectId == subject.id }
            let examDays = exam.map { daysBetween(today, $0.date) }
            let oldest = due.compactMap { parseTimestamp($0.dueAt) }.map { daysBetween(localDate($0, calendar: calendar), today) }.max() ?? 0
            let status: String
            if outdated > 0 { status = "Conferir fonte" }
            else if !due.isEmpty || relearn > 0 { status = "Revisão necessária" }
            else if practiced.isEmpty && done == 0 && studyMinutes == 0 { status = "Ainda sem evidência" }
            else if practiced.count < 5 || (coverage ?? 0) < 25 { status = "Construindo base" }
            else if practiced.count >= 5 && Double(stable) >= Double(practiced.count) / 2 && (coverage ?? 0) >= 50 { status = "Em dia" }
            else { status = "Em consolidação" }
            let confidence = practiced.isEmpty ? "sem evidência" : practiced.count < 5 ? "baixa" : practiced.count < 20 ? "moderada" : "ampla"
            var signals = [cards.isEmpty ? "Nenhum cartão cadastrado; retenção ainda desconhecida." : "\(practiced.count) de \(cards.count) cartões praticados. Cobertura não mede domínio da matéria."]
            if !due.isEmpty { signals.append("\(due.count) revisões previstas; maior atraso: \(max(0, oldest)) dias.") }
            if practiced.contains(where: { $0.lapses > 0 }) { signals.append("Há respostas ‘Não lembrei’ no histórico; isso não prova esquecimento atual.") }
            if outdated > 0 { signals.append("\(outdated) cartões marcados por você para conferir a fonte; não verificamos atualização automaticamente.") }
            if relearn > 0 { signals.append("\(relearn) cartões marcados para reaprender.") }
            if !lessons.isEmpty { signals.append("\(done) de \(lessons.count) aulas marcadas como concluídas.") }
            var priority: Int = min(36, due.count * 4)
            priority += min(10, max(0, oldest))
            priority += min(25, outdated * 5)
            priority += min(16, relearn * 4)
            if let days = examDays, days <= 30 { priority += days <= 2 ? 40 : days <= 7 ? 30 : days <= 14 ? 20 : 10; signals.append("Prova cadastrada em \(days) dias.") }
            if done < lessons.count { priority += 8 }
            return SubjectInsight(subjectId: subject.id, name: subject.name, status: status, confidence: confidence, priority: min(100, priority), signals: signals, totalCards: cards.count, reviewedCards: practiced.count, dueCards: due.count, outdatedCards: outdated, relearnCards: relearn, lessonsDone: done, totalLessons: lessons.count, coveragePercent: coverage, studyMinutes: studyMinutes, nextExam: exam, daysToExam: examDays)
        }
        let insights = unsortedInsights.sorted { $0.priority == $1.priority ? $0.name < $1.name : $0.priority > $1.priority }
        let todayMinutes = minutes[today] ?? 0
        return StudyOverview(dueCards: due.count, reviewCards: due.filter { $0.lastReviewedAt != nil }.count, newCards: due.filter { $0.lastReviewedAt == nil }.count, todayMinutes: todayMinutes, weekMinutes: weekMinutes, streak: streak, lessonsDone: state.lessons.filter { $0.status == .done }.count, totalLessons: state.lessons.count, flaggedCards: state.cards.filter { $0.flag != .none }.count, upcomingExams: exams, todayTasks: state.tasks.filter { $0.date == today }, dailyGoalProgress: min(100, todayMinutes / Double(max(1, state.settings.dailyMinutes)) * 100), subjects: insights, limits: [
            "O diagnóstico resume registros do Ninho; não mede domínio real nem prevê nota em prova.",
            "Cobertura é a parcela de cartões praticados. Aulas concluídas são marcações suas.",
            "Atraso sugere uma oportunidade de praticar. Atualização de conteúdo precisa ser conferida na fonte."
        ])
    }
}
