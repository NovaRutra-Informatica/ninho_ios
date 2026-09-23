import Foundation

public struct StudentProfile: Codable, Equatable, Sendable {
    public var name = ""
    public var goal = ""
    public var motivation = ""
    public var targetDate = ""
    public var routine = ""
    public var availableDays: [String] = ["mon", "tue", "wed", "thu", "fri"]
    public var dailyMinutes = 30
    public var sessionMinutes = 25
    public var preferredTime = ""
    public var preferences = ""
    public var challenges = ""
    public var subjects = ""
    public var level = ""
    public var accessibility = ""
    public var completedAt: String?
    public var updatedAt: String?
    public var revision = 0
    public var plan = ""
    public var planStatus = "none"
    public var planProfileRevision = 0
    public var tutorialsSeen: [String] = []
    public init() {}

    private enum CodingKeys: String, CodingKey { case name, goal, motivation, targetDate, routine, preferredTime, preferences, challenges, subjects, level, accessibility, plan, planStatus, dailyMinutes, sessionMinutes, revision, planProfileRevision, availableDays, tutorialsSeen, completedAt, updatedAt }
    public init(from decoder: Decoder) throws {
        self.init()
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? name
        goal = try box.decodeIfPresent(String.self, forKey: .goal) ?? goal
        motivation = try box.decodeIfPresent(String.self, forKey: .motivation) ?? motivation
        targetDate = try box.decodeIfPresent(String.self, forKey: .targetDate) ?? targetDate
        routine = try box.decodeIfPresent(String.self, forKey: .routine) ?? routine
        preferredTime = try box.decodeIfPresent(String.self, forKey: .preferredTime) ?? preferredTime
        preferences = try box.decodeIfPresent(String.self, forKey: .preferences) ?? preferences
        challenges = try box.decodeIfPresent(String.self, forKey: .challenges) ?? challenges
        subjects = try box.decodeIfPresent(String.self, forKey: .subjects) ?? subjects
        level = try box.decodeIfPresent(String.self, forKey: .level) ?? level
        accessibility = try box.decodeIfPresent(String.self, forKey: .accessibility) ?? accessibility
        plan = try box.decodeIfPresent(String.self, forKey: .plan) ?? plan
        planStatus = try box.decodeIfPresent(String.self, forKey: .planStatus) ?? planStatus
        dailyMinutes = try box.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? dailyMinutes
        sessionMinutes = try box.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? sessionMinutes
        revision = try box.decodeIfPresent(Int.self, forKey: .revision) ?? revision
        planProfileRevision = try box.decodeIfPresent(Int.self, forKey: .planProfileRevision) ?? planProfileRevision
        availableDays = try box.decodeIfPresent([String].self, forKey: .availableDays) ?? availableDays
        tutorialsSeen = try box.decodeIfPresent([String].self, forKey: .tutorialsSeen) ?? tutorialsSeen
        completedAt = try box.decodeIfPresent(String.self, forKey: .completedAt)
        updatedAt = try box.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public var answers: [String: String] {
        ["nome": name, "objetivo": goal, "motivacao": motivation, "prazo": targetDate,
         "rotina": routine, "diasDaSemana": availableDays.sorted().joined(separator: ","),
         "minutosPorDia": String(dailyMinutes), "horarioPreferido": preferredTime,
         "minutosPorSessao": String(sessionMinutes), "metodosPreferidos": preferences, "dificuldades": challenges, "materias": subjects,
         "conhecimentoAtual": level, "adaptacoes": accessibility]
    }

    public func validate() throws {
        let limits = [(name, 100), (goal, 400), (motivation, 300), (targetDate, 40), (routine, 400),
                      (preferredTime, 160), (preferences, 300), (challenges, 400), (subjects, 300),
                      (level, 160), (accessibility, 240)]
        guard limits.allSatisfy({ $0.0.utf16.count <= $0.1 }),
              (1...1440).contains(dailyMinutes), (1...240).contains(sessionMinutes), availableDays.count <= 7,
              Set(availableDays).count == availableDays.count,
              availableDays.allSatisfy({ ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].contains($0) }),
              plan.utf16.count <= 16_000, ["none", "pending", "ready", "error"].contains(planStatus),
              (0...1_000_000).contains(revision), (0...1_000_000).contains(planProfileRevision),
              tutorialsSeen.count <= 32, Set(tutorialsSeen).count == tutorialsSeen.count,
              tutorialsSeen.allSatisfy({ $0.utf8.count <= 80 }),
              updatedAt == nil || StudyEngine.parseTimestamp(updatedAt!) != nil,
              completedAt == nil || StudyEngine.parseTimestamp(completedAt!) != nil else {
            throw StudyError.invalid("Há respostas longas demais ou valores inválidos no perfil. Resuma as respostas e confira seu tempo disponível.")
        }
        if completedAt != nil && (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || availableDays.isEmpty) {
            throw StudyError.invalid("Preencha seu nome, um objetivo e pelo menos um dia disponível.")
        }
    }
}

public enum TutorialPage: String, CaseIterable, Codable, Sendable {
    case today, studies, reviews, focus, materials, agenda, progress, assistant
}
