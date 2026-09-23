import Foundation

public enum SoundCue: String, CaseIterable, Hashable, Sendable {
    case save, review, complete, focusDone
}

public enum StudySounds {
    public static let sampleRate = 22_050

    public static func duration(for cue: SoundCue) -> Double {
        switch cue {
        case .save: return 0.14
        case .review: return 0.20
        case .complete: return 0.34
        case .focusDone: return 0.48
        }
    }

    public static func waveData(for cue: SoundCue) -> Data {
        let notes: [Double]
        switch cue {
        case .save: notes = [659.25, 783.99]
        case .review: notes = [523.25, 659.25]
        case .complete: notes = [659.25, 783.99, 1_046.50]
        case .focusDone: notes = [523.25, 659.25, 880.00]
        }
        let count = Int(duration(for: cue) * Double(sampleRate))
        let size = UInt32(count * 2)
        var data = Data(capacity: 44 + Int(size))
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func integer(_ value: UInt32) { word(UInt16(truncatingIfNeeded: value)); word(UInt16(truncatingIfNeeded: value >> 16)) }
        text("RIFF"); integer(36 + size); text("WAVEfmt "); integer(16)
        word(1); word(1); integer(UInt32(sampleRate)); integer(UInt32(sampleRate * 2)); word(2); word(16)
        text("data"); integer(size)
        for index in 0..<count {
            let position = Double(index) / Double(max(1, count - 1))
            let notePosition = position * Double(notes.count)
            let noteIndex = min(notes.count - 1, Int(notePosition))
            let fraction = min(1, notePosition - Double(noteIndex))
            let envelope = pow(sin(Double.pi * fraction), 2)
            let time = Double(index) / Double(sampleRate)
            let fundamental = sin(2 * Double.pi * notes[noteIndex] * time)
            let overtone = sin(4 * Double.pi * notes[noteIndex] * time) * 0.12
            let sample = Int16(((fundamental + overtone) * envelope * 0.16 * Double(Int16.max)).rounded())
            word(UInt16(bitPattern: sample))
        }
        return data
    }
}

/// Emit cues only after persistence succeeds.
public enum StudySoundPolicy {
    public static func cue(after command: StudyCommand, previous: AppState, updated: AppState) -> SoundCue? {
        guard updated.settings.sound, previous != updated else { return nil }
        switch command {
        case .updateSettings, .updateProfile, .completeTutorial, .resetTutorials: return nil
        case .reviewCard: return .review
        case .updateLesson(let id, let status, _):
            if status == .done && previous.lessons.first(where: { $0.id == id })?.status != .done { return .complete }
            return .save
        case .saveTask(let task):
            if task.completed && previous.tasks.first(where: { $0.id == task.id })?.completed != true { return .complete }
            return .save
        case .saveExam(let exam):
            if exam.completed && previous.exams.first(where: { $0.id == exam.id })?.completed != true { return .complete }
            return .save
        case .addSession(let session):
            return session.kind == .focus && session.durationMinutes > 0 ? .focusDone : nil
        default: return .save
        }
    }
}
