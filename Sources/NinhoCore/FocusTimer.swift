import Foundation

public enum FocusPhase: String, Codable, Sendable { case idle, running, paused, completed }

public enum FocusTimerError: Error, LocalizedError, Equatable, Sendable {
    case invalidSnapshot
    case invalidDuration
    case invalidContext
    case contextLocked
    case completionPending
    case alreadyRunning
    case nothingToResume
    case targetReached
    case wrongCompletion

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot: "A sessão de foco salva está inválida."
        case .invalidDuration: "A duração deve ficar entre 1 segundo e 24 horas."
        case .invalidContext: "Escolha uma matéria válida para vincular a aula."
        case .contextLocked: "Conclua ou reinicie o foco antes de trocar de aula, matéria ou duração."
        case .completionPending: "Salve a sessão concluída antes de começar outra ou reiniciar."
        case .alreadyRunning: "O foco já está em andamento."
        case .nothingToResume: "Não há uma sessão pausada para retomar."
        case .targetReached: "O foco chegou ao fim. Conclua a sessão para registrar o tempo."
        case .wrongCompletion: "A confirmação não pertence a esta sessão de foco."
        }
    }
}

/// Persist pendingSession before addSession; acknowledge only after commit.
public struct FocusSnapshot: Codable, Equatable, Sendable {
    public var sessionId: String
    public var subjectId: String
    public var lessonId: String
    public var targetSeconds: Double
    public var accumulatedSeconds: Double
    public var startedAt: Date?
    public var targetReachedAt: Date?
    public var pendingSession: StudySession?
    public var completed: Bool

    public init(sessionId: String = UUID().uuidString, subjectId: String = "", lessonId: String = "",
                targetSeconds: Double = 25 * 60, accumulatedSeconds: Double = 0, startedAt: Date? = nil,
                targetReachedAt: Date? = nil, pendingSession: StudySession? = nil, completed: Bool = false) {
        self.sessionId = sessionId; self.subjectId = subjectId; self.lessonId = lessonId
        self.targetSeconds = targetSeconds; self.accumulatedSeconds = accumulatedSeconds
        self.startedAt = startedAt; self.targetReachedAt = targetReachedAt
        self.pendingSession = pendingSession; self.completed = completed
    }
}

/// Timestamps preserve elapsed time across suspension and relaunch.
public struct FocusTimer: Codable, Equatable, Sendable {
    public private(set) var snapshot: FocusSnapshot
    public var isRunning: Bool { snapshot.startedAt != nil }
    public var phase: FocusPhase {
        if snapshot.completed { return .completed }
        if isRunning { return .running }
        return snapshot.accumulatedSeconds > 0 ? .paused : .idle
    }
    public var pendingSession: StudySession? { snapshot.pendingSession }

    public init() { snapshot = FocusSnapshot() }
    public init(snapshot: FocusSnapshot) throws {
        try Self.validate(snapshot)
        self.snapshot = snapshot
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(snapshot: container.decode(FocusSnapshot.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(snapshot)
    }

    public func elapsedSeconds(at now: Date = Date()) -> Double {
        let segment = snapshot.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        guard segment.isFinite else { return snapshot.accumulatedSeconds }
        return min(snapshot.targetSeconds, snapshot.accumulatedSeconds + segment)
    }

    public func remainingSeconds(at now: Date = Date()) -> Double {
        max(0, snapshot.targetSeconds - elapsedSeconds(at: now))
    }

    public mutating func configure(subjectId: String, lessonId: String = "", minutes: Double) throws {
        let seconds = minutes * 60
        guard seconds.isFinite, seconds >= 1, seconds <= 86_400 else { throw FocusTimerError.invalidDuration }
        guard Self.validID(subjectId, empty: true), Self.validID(lessonId, empty: true), lessonId.isEmpty || !subjectId.isEmpty else { throw FocusTimerError.invalidContext }
        guard snapshot.pendingSession == nil else { throw FocusTimerError.completionPending }
        let unchanged = snapshot.subjectId == subjectId && snapshot.lessonId == lessonId && snapshot.targetSeconds == seconds
        if !snapshot.completed && (isRunning || snapshot.accumulatedSeconds > 0) {
            guard unchanged else { throw FocusTimerError.contextLocked }
            return
        }
        if unchanged && !snapshot.completed { return }
        snapshot = FocusSnapshot(subjectId: subjectId, lessonId: lessonId, targetSeconds: seconds)
    }

    public mutating func start(at now: Date = Date()) throws {
        try Self.validateDate(now)
        guard snapshot.pendingSession == nil else { throw FocusTimerError.completionPending }
        guard !isRunning else { throw FocusTimerError.alreadyRunning }
        if snapshot.completed { try reset() }
        guard snapshot.accumulatedSeconds < snapshot.targetSeconds else { throw FocusTimerError.targetReached }
        snapshot.startedAt = now
    }

    public mutating func pause(at now: Date = Date()) throws {
        try Self.validateDate(now)
        guard let start = snapshot.startedAt else { return }
        let elapsed = elapsedSeconds(at: now)
        if elapsed >= snapshot.targetSeconds {
            snapshot.targetReachedAt = start.addingTimeInterval(snapshot.targetSeconds - snapshot.accumulatedSeconds)
        }
        snapshot.accumulatedSeconds = elapsed
        snapshot.startedAt = nil
    }

    public mutating func resume(at now: Date = Date()) throws {
        guard snapshot.pendingSession == nil else { throw FocusTimerError.completionPending }
        guard phase == .paused else { throw FocusTimerError.nothingToResume }
        try start(at: now)
    }

    /// An uncommitted completion cannot be discarded.
    public mutating func reset() throws {
        guard snapshot.pendingSession == nil else { throw FocusTimerError.completionPending }
        snapshot = FocusSnapshot(subjectId: snapshot.subjectId, lessonId: snapshot.lessonId, targetSeconds: snapshot.targetSeconds)
    }

    /// Retries preserve the session; skip addSession if its ID is already stored.
    public mutating func finish(at now: Date = Date()) throws -> StudySession? {
        try Self.validateDate(now)
        if let pending = snapshot.pendingSession { return pending }
        guard !snapshot.completed else { return nil }
        try pause(at: now)
        guard snapshot.accumulatedSeconds > 0 else { return nil }
        let completedAt = min(now, snapshot.targetReachedAt ?? now)
        let session = StudySession(id: snapshot.sessionId, subjectId: snapshot.subjectId, lessonId: snapshot.lessonId,
                                   durationMinutes: snapshot.accumulatedSeconds / 60,
                                   completedAt: StudyEngine.timestamp(completedAt), kind: .focus)
        snapshot.pendingSession = session
        snapshot.completed = true
        return session
    }

    public mutating func acknowledgeCompletion(sessionID: String) throws {
        guard snapshot.completed, sessionID == snapshot.sessionId else { throw FocusTimerError.wrongCompletion }
        snapshot.pendingSession = nil
    }

    private static func validID(_ value: String, empty: Bool) -> Bool {
        if value.isEmpty { return empty }
        return value.utf16.count <= 200 && value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]*$"#, options: .regularExpression) != nil
    }
    private static func validateDate(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw FocusTimerError.invalidSnapshot }
    }
    private static func validate(_ value: FocusSnapshot) throws {
        guard validID(value.sessionId, empty: false), validID(value.subjectId, empty: true), validID(value.lessonId, empty: true),
              value.lessonId.isEmpty || !value.subjectId.isEmpty,
              value.targetSeconds.isFinite, value.targetSeconds >= 1, value.targetSeconds <= 86_400,
              value.accumulatedSeconds.isFinite, value.accumulatedSeconds >= 0, value.accumulatedSeconds <= value.targetSeconds,
              !value.completed || (value.startedAt == nil && value.accumulatedSeconds > 0),
              value.startedAt == nil || value.accumulatedSeconds < value.targetSeconds else { throw FocusTimerError.invalidSnapshot }
        if let date = value.startedAt { try validateDate(date) }
        if let date = value.targetReachedAt {
            try validateDate(date)
            guard value.accumulatedSeconds == value.targetSeconds else { throw FocusTimerError.invalidSnapshot }
        }
        if let session = value.pendingSession {
            guard value.completed, session.id == value.sessionId, session.subjectId == value.subjectId,
                  session.lessonId == value.lessonId, session.kind == .focus,
                  session.durationMinutes == value.accumulatedSeconds / 60,
                  StudyEngine.parseTimestamp(session.completedAt) != nil else { throw FocusTimerError.invalidSnapshot }
        }
    }
}
