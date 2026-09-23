import Foundation

/// UI progress is separate from the durable answers and from profile completion.
public enum WelcomeJourney {
    public static let questionCount = 10
    public static let reviewStep = questionCount

    public static func canContinue(profile: StudentProfile, step: Int) -> Bool {
        switch step {
        case 0: return !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1: return !profile.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 6: return !profile.availableDays.isEmpty
        default: return (0...reviewStep).contains(step)
        }
    }

    public static func resumeStep(saved: Int, profile: StudentProfile?) -> Int {
        guard let profile, profile.completedAt == nil else { return 0 }
        var step = min(reviewStep, max(0, saved))
        for required in [0, 1, 6] where required < step && !canContinue(profile: profile, step: required) { step = required }
        return step
    }
}
