import Foundation

public enum Track: String, Codable, CaseIterable, Sendable { case concurso, faculdade, pessoal }
public enum Theme: String, Codable, CaseIterable, Sendable { case light, dark, system }
public enum LessonStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "not-started", inProgress = "in-progress", done
}
public enum Rating: String, Codable, CaseIterable, Sendable { case again, hard, good, easy }
public enum CardFlag: String, Codable, CaseIterable, Sendable { case none, outdated, relearn }
public enum SessionKind: String, Codable, CaseIterable, Sendable { case focus, lesson, review }

public struct Settings: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "settings" }
    public var name: String
    public var dailyMinutes: Int
    public var newCardsPerDay: Int
    public var focusMinutes: Int
    public var breakMinutes: Int
    public var theme: Theme
    public var sound: Bool
    public var reducedMotion: Bool
    public init(name: String = "Alessandro", dailyMinutes: Int = 30, newCardsPerDay: Int = 5,
                focusMinutes: Int = 25, breakMinutes: Int = 5, theme: Theme = .light,
                sound: Bool = false, reducedMotion: Bool = false) {
        self.name = name; self.dailyMinutes = dailyMinutes; self.newCardsPerDay = newCardsPerDay
        self.focusMinutes = focusMinutes; self.breakMinutes = breakMinutes; self.theme = theme
        self.sound = sound; self.reducedMotion = reducedMotion
    }
}

public struct StudyProgram: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var track: Track
    public var color: String
    public var description: String
    public init(id: String = UUID().uuidString, name: String = "", track: Track = .pessoal,
                color: String = "#527969", description: String = "") {
        self.id = id; self.name = name; self.track = track; self.color = color; self.description = description
    }
}

public struct Subject: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var programId: String
    public var name: String
    public var track: Track
    public var color: String
    public init(id: String = UUID().uuidString, programId: String = "", name: String = "",
                track: Track = .pessoal, color: String = "#527969") {
        self.id = id; self.programId = programId; self.name = name; self.track = track; self.color = color
    }
}

/// A module/source inside a subject. The top-level UI course is StudyProgram.
public struct Course: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subjectId: String
    public var title: String
    public var provider: String
    public var url: String
    public init(id: String = UUID().uuidString, subjectId: String = "", title: String = "",
                provider: String = "Material próprio", url: String = "") {
        self.id = id; self.subjectId = subjectId; self.title = title; self.provider = provider; self.url = url
    }
}

public struct Lesson: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var courseId: String
    public var subjectId: String
    public var title: String
    public var description: String
    public var url: String
    public var order: Int
    public var status: LessonStatus
    public var updatedAt: String?
    public var notes: String
    public init(id: String = UUID().uuidString, courseId: String = "", subjectId: String = "",
                title: String = "", description: String = "", url: String = "", order: Int = 0,
                status: LessonStatus = .notStarted, updatedAt: String? = nil, notes: String = "") {
        self.id = id; self.courseId = courseId; self.subjectId = subjectId; self.title = title
        self.description = description; self.url = url; self.order = order; self.status = status
        self.updatedAt = updatedAt; self.notes = notes
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id); try box.encode(courseId, forKey: .courseId)
        try box.encode(subjectId, forKey: .subjectId); try box.encode(title, forKey: .title)
        try box.encode(description, forKey: .description); try box.encode(url, forKey: .url)
        try box.encode(order, forKey: .order); try box.encode(status, forKey: .status)
        try box.encode(updatedAt, forKey: .updatedAt); try box.encode(notes, forKey: .notes)
    }
}

public struct ReviewCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subjectId: String
    public var lessonId: String?
    public var question: String
    public var answer: String
    public var source: String
    public var sourceUrl: String
    public var dueAt: String
    public var lastReviewedAt: String?
    public var intervalDays: Double
    public var ease: Double
    public var repetitions: Int
    public var lapses: Int
    public var flag: CardFlag
    public var suspended: Bool
    public var createdAt: String
    public init(id: String = UUID().uuidString, subjectId: String = "", lessonId: String? = nil,
                question: String = "", answer: String = "", source: String = "", sourceUrl: String = "",
                dueAt: String? = nil, lastReviewedAt: String? = nil,
                intervalDays: Double = 0, ease: Double = 2.5, repetitions: Int = 0, lapses: Int = 0,
                flag: CardFlag = .none, suspended: Bool = false,
                createdAt: String = StudyEngine.timestamp(Date())) {
        self.id = id; self.subjectId = subjectId; self.lessonId = lessonId; self.question = question
        self.answer = answer; self.source = source; self.sourceUrl = sourceUrl; self.dueAt = dueAt ?? createdAt
        self.lastReviewedAt = lastReviewedAt; self.intervalDays = intervalDays; self.ease = ease
        self.repetitions = repetitions; self.lapses = lapses; self.flag = flag
        self.suspended = suspended; self.createdAt = createdAt
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id); try box.encode(subjectId, forKey: .subjectId)
        try box.encodeIfPresent(lessonId, forKey: .lessonId)
        try box.encode(question, forKey: .question); try box.encode(answer, forKey: .answer)
        try box.encode(source, forKey: .source); try box.encode(sourceUrl, forKey: .sourceUrl)
        try box.encode(dueAt, forKey: .dueAt); try box.encode(lastReviewedAt, forKey: .lastReviewedAt)
        try box.encode(intervalDays, forKey: .intervalDays); try box.encode(ease, forKey: .ease)
        try box.encode(repetitions, forKey: .repetitions); try box.encode(lapses, forKey: .lapses)
        try box.encode(flag, forKey: .flag); try box.encode(suspended, forKey: .suspended)
        try box.encode(createdAt, forKey: .createdAt)
    }
}

public struct Exam: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subjectId: String
    public var date: String
    public var time: String
    public var location: String
    public var notes: String
    public var completed: Bool
    public init(id: String = UUID().uuidString, title: String = "", subjectId: String = "",
                date: String = StudyEngine.localDate(Date()), time: String = "", location: String = "",
                notes: String = "", completed: Bool = false) {
        self.id = id; self.title = title; self.subjectId = subjectId; self.date = date; self.time = time
        self.location = location; self.notes = notes; self.completed = completed
    }
}

public struct Material: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var storedName: String
    public var type: String
    public var size: Int
    public var subjectId: String
    public var lessonId: String
    public var createdAt: String
    public var notes: String
    public init(id: String = UUID().uuidString, name: String = "", storedName: String = "",
                type: String = "pdf", size: Int = 0, subjectId: String = "", lessonId: String = "",
                createdAt: String = StudyEngine.timestamp(Date()), notes: String = "") {
        self.id = id; self.name = name; self.storedName = storedName; self.type = type; self.size = size
        self.subjectId = subjectId; self.lessonId = lessonId; self.createdAt = createdAt; self.notes = notes
    }
}

public struct StudySession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subjectId: String
    public var lessonId: String
    public var durationMinutes: Double
    public var completedAt: String
    public var kind: SessionKind
    public init(id: String = UUID().uuidString, subjectId: String = "", lessonId: String = "",
                durationMinutes: Double = 0, completedAt: String = StudyEngine.timestamp(Date()),
                kind: SessionKind = .focus) {
        self.id = id; self.subjectId = subjectId; self.lessonId = lessonId
        self.durationMinutes = durationMinutes; self.completedAt = completedAt; self.kind = kind
    }
}

public struct StudyTask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var date: String
    public var subjectId: String
    public var completed: Bool
    public init(id: String = UUID().uuidString, title: String = "", date: String = StudyEngine.localDate(Date()),
                subjectId: String = "", completed: Bool = false) {
        self.id = id; self.title = title; self.date = date; self.subjectId = subjectId; self.completed = completed
    }
}

public struct AppState: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "ninho" }
    public var version: Int
    public var settings: Settings
    public var programs: [StudyProgram]
    public var subjects: [Subject]
    public var courses: [Course]
    public var lessons: [Lesson]
    public var cards: [ReviewCard]
    public var exams: [Exam]
    public var materials: [Material]
    public var sessions: [StudySession]
    public var tasks: [StudyTask]
    public var profile: StudentProfile?
    public init(version: Int = 2, settings: Settings = Settings(), programs: [StudyProgram] = [],
                subjects: [Subject] = [], courses: [Course] = [], lessons: [Lesson] = [], cards: [ReviewCard] = [],
                exams: [Exam] = [], materials: [Material] = [], sessions: [StudySession] = [], tasks: [StudyTask] = [],
                profile: StudentProfile? = nil) {
        self.version = version; self.settings = settings; self.programs = programs; self.subjects = subjects
        self.courses = courses; self.lessons = lessons; self.cards = cards; self.exams = exams
        self.materials = materials; self.sessions = sessions; self.tasks = tasks
        self.profile = profile
    }
}

public enum StudyCommand: Equatable, Sendable {
    case saveProgram(StudyProgram), saveSubject(Subject), saveCourse(Course), saveLesson(Lesson)
    case updateLesson(id: String, status: LessonStatus? = nil, notes: String? = nil)
    case saveCard(ReviewCard), reviewCard(id: String, rating: Rating)
    case flagCard(id: String, flag: CardFlag), suspendCard(id: String, suspended: Bool), deleteCard(id: String)
    case saveExam(Exam), deleteExam(id: String), saveTask(StudyTask), deleteTask(id: String)
    case addSession(StudySession)
    case updateMaterial(id: String, subjectId: String? = nil, lessonId: String? = nil, notes: String? = nil)
    case removeMaterial(id: String), addMaterial(Material), updateSettings(Settings)
    case updateProfile(StudentProfile), completeTutorial(TutorialPage), resetTutorials
}

public struct LessonStudyStats: Codable, Equatable, Sendable {
    public var durationMinutes: Double
    public var sessionCount: Int
    public init(durationMinutes: Double = 0, sessionCount: Int = 0) {
        self.durationMinutes = durationMinutes; self.sessionCount = sessionCount
    }
}

public struct SubjectInsight: Codable, Equatable, Sendable, Identifiable {
    public var id: String { subjectId }
    public var subjectId: String
    public var name: String
    public var status: String
    public var confidence: String
    public var priority: Int
    public var signals: [String]
    public var totalCards: Int
    public var reviewedCards: Int
    public var dueCards: Int
    public var outdatedCards: Int
    public var relearnCards: Int
    public var lessonsDone: Int
    public var totalLessons: Int
    public var coveragePercent: Double?
    public var studyMinutes: Double
    public var nextExam: Exam?
    public var daysToExam: Int?
    public init(subjectId: String = "", name: String = "", status: String = "Ainda sem evidência",
                confidence: String = "sem evidência", priority: Int = 0, signals: [String] = [],
                totalCards: Int = 0, reviewedCards: Int = 0, dueCards: Int = 0, outdatedCards: Int = 0,
                relearnCards: Int = 0, lessonsDone: Int = 0, totalLessons: Int = 0,
                coveragePercent: Double? = nil, studyMinutes: Double = 0, nextExam: Exam? = nil,
                daysToExam: Int? = nil) {
        self.subjectId = subjectId; self.name = name; self.status = status; self.confidence = confidence
        self.priority = priority; self.signals = signals; self.totalCards = totalCards; self.reviewedCards = reviewedCards
        self.dueCards = dueCards; self.outdatedCards = outdatedCards; self.relearnCards = relearnCards
        self.lessonsDone = lessonsDone; self.totalLessons = totalLessons; self.coveragePercent = coveragePercent
        self.studyMinutes = studyMinutes; self.nextExam = nextExam; self.daysToExam = daysToExam
    }
}

public struct StudyOverview: Codable, Equatable, Sendable {
    public var dueCards: Int
    public var reviewCards: Int
    public var newCards: Int
    public var todayMinutes: Double
    public var weekMinutes: Double
    public var streak: Int
    public var lessonsDone: Int
    public var totalLessons: Int
    public var flaggedCards: Int
    public var upcomingExams: [Exam]
    public var todayTasks: [StudyTask]
    public var dailyGoalProgress: Double
    public var subjects: [SubjectInsight]
    public var limits: [String]
    public init(dueCards: Int = 0, reviewCards: Int = 0, newCards: Int = 0, todayMinutes: Double = 0,
                weekMinutes: Double = 0, streak: Int = 0, lessonsDone: Int = 0, totalLessons: Int = 0,
                flaggedCards: Int = 0, upcomingExams: [Exam] = [], todayTasks: [StudyTask] = [],
                dailyGoalProgress: Double = 0, subjects: [SubjectInsight] = [], limits: [String] = []) {
        self.dueCards = dueCards; self.reviewCards = reviewCards; self.newCards = newCards; self.todayMinutes = todayMinutes
        self.weekMinutes = weekMinutes; self.streak = streak; self.lessonsDone = lessonsDone; self.totalLessons = totalLessons
        self.flaggedCards = flaggedCards; self.upcomingExams = upcomingExams; self.todayTasks = todayTasks
        self.dailyGoalProgress = dailyGoalProgress; self.subjects = subjects; self.limits = limits
    }
}
