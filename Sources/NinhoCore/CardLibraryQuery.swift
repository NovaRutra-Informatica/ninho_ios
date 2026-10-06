import Foundation

public enum CardLibraryQuery {
    public static func search(_ cards: [ReviewCard], subjectID: String = "", lessonID: String = "", text: String = "") throws -> [ReviewCard] {
        try Task.checkCancellation()
        if subjectID.isEmpty && lessonID.isEmpty && text.isEmpty { return cards }
        var result: [ReviewCard] = []
        for (index, card) in cards.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard (subjectID.isEmpty || card.subjectId == subjectID),
                  (lessonID.isEmpty || card.lessonId == lessonID),
                  (text.isEmpty || card.question.localizedCaseInsensitiveContains(text)) else { continue }
            result.append(card)
        }
        try Task.checkCancellation()
        return result
    }
}
