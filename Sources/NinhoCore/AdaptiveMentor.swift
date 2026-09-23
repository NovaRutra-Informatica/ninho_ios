import Foundation

public enum MentorRoute: String, Codable, CaseIterable, Sendable {
    case today, studies, reviews, focus, materials, agenda, progress, assistant, profile, settings, more
}

public struct RouteActivity: Codable, Equatable, Sendable {
    public var visits = 0
    public var seconds: Double = 0
    public init() {}
}

public struct ActivityDay: Codable, Equatable, Sendable {
    public var date: String
    public var routes: [String: RouteActivity] = [:]
    public var focusStarts = 0
    public var pausedSessions = 0
    public var focusFinished = 0
    public var earlyFinishes = 0
    public var discarded = 0
    /// Eight three-hour buckets; these are observed starts, never inferred from completion times.
    public var startHours: [Int] = Array(repeating: 0, count: 8)
    public init(date: String) { self.date = date }
}

public struct LocalActivity: Codable, Equatable, Sendable {
    public var trackingEnabled = true
    public var days: [ActivityDay] = []
    public private(set) var trackedFocusID: String?
    public private(set) var trackedFocusDay: String?
    public private(set) var trackedFocusPaused = false
    public init() {}

    public func validate() throws {
        guard days.count <= 90, Set(days.map(\.date)).count == days.count,
              (trackedFocusID?.utf8.count ?? 0) <= 160,
              (trackedFocusDay?.utf8.count ?? 0) <= 10 else { throw LibraryError.invalid("Histórico local de uso inválido.") }
        for day in days {
            guard day.date.count == 10, StudyEngine.parseTimestamp(day.date + "T12:00:00Z") != nil,
                  day.routes.count <= MentorRoute.allCases.count,
                  day.startHours.count == 8, day.startHours.allSatisfy({ (0...10000).contains($0) }),
                  [day.focusStarts, day.pausedSessions, day.focusFinished, day.earlyFinishes, day.discarded].allSatisfy({ (0...10000).contains($0) }),
                  day.pausedSessions <= day.focusStarts, day.earlyFinishes <= day.focusFinished,
                  day.focusFinished + day.discarded <= day.focusStarts,
                  day.startHours.reduce(0, +) == day.focusStarts,
                  day.routes.values.reduce(0, { $0 + $1.seconds }) <= 86400 else { throw LibraryError.invalid("Agregado diário inválido.") }
            for (route, value) in day.routes {
                guard MentorRoute(rawValue: route) != nil, (0...10000).contains(value.visits), value.seconds.isFinite,
                      (0...86400).contains(value.seconds) else { throw LibraryError.invalid("Uso de tela inválido.") }
            }
        }
    }

    public mutating func prune(at date: Date, calendar: Calendar = .current) {
        let today = StudyEngine.localDate(date, calendar: calendar)
        let oldest = StudyEngine.localDate(calendar.date(byAdding: .day, value: -89, to: date) ?? date, calendar: calendar)
        days.removeAll { $0.date < oldest || $0.date > today }
        days.sort { $0.date < $1.date }
        if days.count > 90 { days = Array(days.suffix(90)) }
        if trackedFocusID != nil && !days.contains(where: { $0.date == trackedFocusDay }) {
            trackedFocusID = nil; trackedFocusDay = nil; trackedFocusPaused = false
        }
    }

    private mutating func dayIndex(at date: Date, calendar: Calendar) -> Int {
        prune(at: date, calendar: calendar)
        let key = StudyEngine.localDate(date, calendar: calendar)
        if let index = days.firstIndex(where: { $0.date == key }) { return index }
        days.append(ActivityDay(date: key)); return days.count - 1
    }

    public mutating func visit(_ route: MentorRoute, at date: Date, calendar: Calendar = .current) {
        guard trackingEnabled else { return }
        let index = dayIndex(at: date, calendar: calendar)
        var value = days[index].routes[route.rawValue] ?? RouteActivity()
        value.visits = min(10000, value.visits + 1); days[index].routes[route.rawValue] = value
    }

    /// Caller supplies foreground-only elapsed time. Split at midnight; cap to one day per flush.
    public mutating func addForeground(_ route: MentorRoute, from start: Date, seconds: Double, calendar: Calendar = .current) {
        guard trackingEnabled, seconds.isFinite, seconds > 0 else { return }
        var cursor = start, remaining = min(86400, seconds)
        while remaining > 0 {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? cursor.addingTimeInterval(86400)
            let chunk = min(remaining, max(1, nextDay.timeIntervalSince(cursor)))
            let index = dayIndex(at: cursor, calendar: calendar)
            var value = days[index].routes[route.rawValue] ?? RouteActivity()
            let already = days[index].routes.values.reduce(0, { $0 + $1.seconds })
            value.seconds += min(chunk, max(0, 86400 - already))
            days[index].routes[route.rawValue] = value
            remaining -= chunk; cursor = cursor.addingTimeInterval(chunk)
        }
    }

    public mutating func focusStarted(id: String, at date: Date, calendar: Calendar = .current) {
        guard id != trackedFocusID else { return }
        let index = dayIndex(at: date, calendar: calendar)
        guard days[index].focusStarts < 10000 else { return }
        trackedFocusID = id; trackedFocusDay = days[index].date; trackedFocusPaused = false
        days[index].focusStarts += 1
        days[index].startHours[calendar.component(.hour, from: date) / 3] += 1
    }

    public mutating func focusPaused(id: String) {
        guard trackedFocusID == id, !trackedFocusPaused else { return }
        trackedFocusPaused = true
        if let index = days.firstIndex(where: { $0.date == trackedFocusDay }) { days[index].pausedSessions = min(10000, days[index].pausedSessions + 1) }
    }

    public mutating func focusEnded(id: String, early: Bool, discarded: Bool = false) {
        guard trackedFocusID == id else { return }
        if let index = days.firstIndex(where: { $0.date == trackedFocusDay }) {
            if discarded { days[index].discarded = min(10000, days[index].discarded + 1) }
            else {
                days[index].focusFinished = min(10000, days[index].focusFinished + 1)
                if early { days[index].earlyFinishes = min(10000, days[index].earlyFinishes + 1) }
            }
        }
        trackedFocusID = nil; trackedFocusDay = nil; trackedFocusPaused = false
    }
}

public struct MentorSuggestion: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var evidence: String
    public var confidence: String
    public var route: MentorRoute
    public var subjectID = ""
}

public struct MentorReport: Equatable, Sendable {
    public var suggestions: [MentorSuggestion] = []
    public var plan = ""
    public var sampleDescription = "Aguardando seus registros locais."
    public var activeMinutes: Double = 0
    public var visits = 0
    public var generatedAt: Date?
    public init() {}
}

public enum AdaptiveMentor {
    /// Beta(1,3) posterior mean: a single difficult answer cannot produce a 100% difficulty claim.
    public static func smoothedDifficulty(again: Int, answers: Int) -> Double? {
        guard answers >= 8, again >= 0, again <= answers else { return nil }
        return Double(again + 1) / Double(answers + 4)
    }

    public static func analyze(_ state: AppState, activity: LocalActivity = LocalActivity(), overview suppliedOverview: StudyOverview? = nil, at date: Date = Date(), calendar: Calendar = .current) throws -> MentorReport {
        try Task.checkCancellation()
        try activity.validate()
        var recent = activity; recent.prune(at: date, calendar: calendar)
        let overview = suppliedOverview ?? StudyEngine.overview(in: state, at: date, calendar: calendar)
        var report = MentorReport(); report.generatedAt = date
        report.activeMinutes = recent.days.reduce(0, { $0 + $1.routes.values.reduce(0, { $0 + $1.seconds }) }) / 60
        report.visits = recent.days.reduce(0, { $0 + $1.routes.values.reduce(0, { $0 + $1.visits }) })
        let reviewed = state.cards.filter { !$0.suspended && $0.lastReviewedAt != nil }
        let reviewedBySubject = Dictionary(grouping: reviewed, by: \.subjectId)
        let sessionsBySubject = Dictionary(grouping: state.sessions.filter { $0.durationMinutes > 0 }, by: \.subjectId)
        report.sampleDescription = "\(reviewed.count) cartões praticados · \(state.sessions.count) sessões registradas. Cobertura e dificuldade relatada não são medidas de domínio."
        for subject in overview.subjects {
            try Task.checkCancellation()
            if subject.dueCards > 0 {
                report.suggestions.append(.init(id: "review-" + subject.subjectId, title: "Vamos retomar \(subject.name)?", detail: "Comece por uma pequena rodada de revisões que chegaram à data programada.", evidence: "\(subject.dueCards) cartões com revisão prevista. A data não prova que você esqueceu.", confidence: "Agenda registrada", route: .reviews, subjectID: subject.subjectId))
            }
            let cards = reviewedBySubject[subject.subjectId] ?? []
            let answers = cards.reduce(0) { $0 + $1.repetitions }, again = cards.reduce(0) { $0 + $1.lapses }
            if cards.count >= 3, let rate = smoothedDifficulty(again: again, answers: answers), rate >= 0.35 {
                report.suggestions.append(.init(id: "difficulty-" + subject.subjectId, title: "Um pouco mais de apoio em \(subject.name)", detail: "Retome uma explicação antes de tentar os cartões novamente. Você pode ajustar suas preferências no perfil.", evidence: "\(again) avaliações ‘Não lembrei’ em \(answers) respostas históricas de \(cards.count) cartões. Taxa suavizada de dificuldade relatada: \(Int((rate * 100).rounded()))%. São autoavaliações, não acertos verificados; o histórico pode incluir períodos antigos.", confidence: answers >= 30 && cards.count >= 5 ? "Sinal mais consistente" : "Sinal inicial", route: .studies, subjectID: subject.subjectId))
            }
            if subject.lessonsDone > 0 && subject.reviewedCards == 0 {
                report.suggestions.append(.init(id: "coverage-" + subject.subjectId, title: "Teste sua lembrança em \(subject.name)", detail: "Você já registrou aulas concluídas. Experimente criar e praticar algumas perguntas para ter evidência da sua lembrança.", evidence: "\(subject.lessonsDone) aulas concluídas e nenhum cartão praticado. Isso é ausência de prática registrada, não uma lacuna comprovada de conhecimento.", confidence: "Evidência ainda limitada", route: .reviews, subjectID: subject.subjectId))
            }
            if subject.relearnCards > 0 || subject.outdatedCards > 0 {
                report.suggestions.append(.init(id: "flags-" + subject.subjectId, title: "Confira seus lembretes em \(subject.name)", detail: "Retome os cartões que você sinalizou antes de seguir para mais conteúdo.", evidence: "\(subject.relearnCards) cartões marcados para reaprender e \(subject.outdatedCards) para conferir a fonte. São marcações suas, sem verificação automática do conteúdo.", confidence: "Marcado por você", route: .reviews, subjectID: subject.subjectId))
            }
            if let latest = (sessionsBySubject[subject.subjectId] ?? []).compactMap({ StudyEngine.parseTimestamp($0.completedAt) }).max() {
                let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest), to: calendar.startOfDay(for: date)).day ?? 0
                if gap >= 7 && subject.dueCards == 0 {
                    report.suggestions.append(.init(id: "gap-" + subject.subjectId, title: "Que tal reencontrar \(subject.name)?", detail: "Uma pequena retomada pode ajudar você a decidir o próximo passo.", evidence: "Há \(gap) dias sem sessão de estudo registrada nesta matéria. Você pode ter estudado fora do Ninho; ausência de registro não prova esquecimento.", confidence: "Intervalo nos registros", route: .studies, subjectID: subject.subjectId))
                }
            }
            if report.suggestions.count >= 6 { break }
        }
        if let exam = overview.upcomingExams.first {
            report.suggestions.insert(.init(id: "exam-" + exam.id, title: "Prepare espaço para \(exam.title)", detail: "Distribua a preparação nos dias disponíveis do seu perfil e confira o que ainda precisa estudar.", evidence: "Prova cadastrada para \(exam.date).", confidence: "Data informada por você", route: .agenda, subjectID: exam.subjectId), at: 0)
        }
        let starts = recent.days.reduce(0) { $0 + $1.focusStarts }
        let observedDays = recent.days.filter { $0.focusStarts > 0 }.count
        if starts >= 6 && observedDays >= 3 {
            let hours = (0..<8).map { bucket in recent.days.reduce(0) { $0 + $1.startHours[bucket] } }
            if let bucket = hours.indices.max(by: { hours[$0] < hours[$1] }), Double(hours[bucket] + 1) / Double(starts + 8) >= 0.35 {
                report.suggestions.append(.init(id: "habit", title: "Um horário que já faz parte da sua rotina", detail: "Se ainda funcionar para você, reserve um bloco entre \(bucket * 3)h e \(bucket * 3 + 3)h.", evidence: "\(hours[bucket]) de \(starts) inícios de foco registrados, em \(observedDays) dias. É frequência de uso, não o seu horário de melhor desempenho.", confidence: starts >= 20 ? "Hábito observado" : "Sinal inicial", route: .profile))
            }
            let pauses = recent.days.reduce(0) { $0 + $1.pausedSessions }
            let ends = recent.days.reduce(0) { $0 + $1.focusFinished }
            let early = recent.days.reduce(0) { $0 + $1.earlyFinishes }
            if pauses >= 3 || (ends >= 6 && early >= 3 && Double(early + 1) / Double(ends + 4) >= 0.4) {
                report.suggestions.append(.init(id: "breaks", title: "Seu plano pode ter espaço para pausas", detail: "Experimente um bloco mais curto se as interrupções fizerem parte da sua rotina. Ajuste o tempo no foco ou no perfil.", evidence: "\(pauses) de \(starts) sessões foram pausadas; \(early) de \(ends) sessões encerraram antes de 80% do tempo escolhido. Pausas não são tratadas como falta de atenção.", confidence: "Ações registradas no Ninho", route: .focus))
            }
        }
        if report.suggestions.isEmpty {
            report.suggestions.append(.init(id: "begin", title: "Vamos construir seu ritmo aos poucos?", detail: "Escolha uma aula e registre um pequeno bloco de foco. As próximas sugestões vão acompanhar o que você registrar.", evidence: "Ainda não há evidência suficiente para inferir dificuldades ou horários habituais.", confidence: "Começando a conhecer seu ritmo", route: .focus))
        }
        report.suggestions = Array(report.suggestions.prefix(9))
        report.plan = plan(for: state.profile, settings: state.settings, next: report.suggestions.first)
        return report
    }

    private static func plan(for profile: StudentProfile?, settings: Settings, next: MentorSuggestion?) -> String {
        let daily = max(1, min(1440, profile?.dailyMinutes ?? settings.dailyMinutes))
        let block = max(1, min(daily, profile?.sessionMinutes ?? settings.focusMinutes))
        let names = ["mon": "segunda", "tue": "terça", "wed": "quarta", "thu": "quinta", "fri": "sexta", "sat": "sábado", "sun": "domingo"]
        let days = (profile?.availableDays ?? []).compactMap { names[$0] }.joined(separator: ", ")
        let goal = profile?.goal ?? ""
        var lines = ["Plano local inicial — análise embutida do Ninho.", "Objetivo: \(goal.isEmpty ? "avançar nos estudos cadastrados" : goal).",
                     "Reserve \(daily) minutos de estudo em cada dia escolhido\(days.isEmpty ? "" : ": " + days).",
                     "Use \(daily / block) bloco(s) de \(block) minutos\(daily % block > 0 ? " e um bloco de \(daily % block) minutos" : ""). As pausas ficam fora do tempo de estudo."]
        if let next { lines.append("Próximo passo: \(next.title) \(next.detail)") }
        if let profile {
            for (label, value) in [("Sua motivação", profile.motivation), ("Ponto de partida informado", profile.level), ("Horário escolhido", profile.preferredTime), ("Matérias informadas", profile.subjects), ("Prazo informado", profile.targetDate), ("Sua rotina", profile.routine), ("Suas preferências", profile.preferences), ("Dificuldades que você relatou", profile.challenges), ("Adaptações que você pediu", profile.accessibility)] where !value.isEmpty { lines.append("\(label): \(value)") }
        }
        lines.append("Nos dias sem disponibilidade, descanse ou ajuste o perfil. Este planejamento organiza tempos e registros. Os textos livres permanecem como preferências para você consultar; não são interpretados automaticamente por um modelo de linguagem.")
        return lines.joined(separator: "\n\n")
    }
}
