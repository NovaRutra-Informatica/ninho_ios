import Foundation
import NinhoWidgetSupport

public enum StudyStreak {
    public static func countsAsStudy(_ session: StudySession) -> Bool {
        session.durationMinutes.isFinite && session.durationMinutes >= 0 &&
            (session.durationMinutes > 0 || session.kind == .review)
    }

    public static func activeDays(in sessions: [StudySession], at now: Date, calendar: Calendar = .current) -> Set<String> {
        Set(sessions.compactMap { session in
            guard countsAsStudy(session), let completed = StudyEngine.parseTimestamp(session.completedAt), completed <= now else { return nil }
            return StudyEngine.localDate(completed, calendar: calendar)
        })
    }

    /// Calendar days, including DST, with the current streak held through today
    /// when yesterday was the most recent study day.
    public static func current(activeDays: Set<String>, at now: Date, calendar: Calendar = .current) -> Int {
        let today = StudyEngine.localDate(now, calendar: calendar)
        var day = activeDays.contains(today) ? now : (calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        var result = 0
        while activeDays.contains(StudyEngine.localDate(day, calendar: calendar)) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day), previous < day else { break }
            day = previous
        }
        return result
    }
}

public enum WidgetSummary {
    public static func make(state: AppState, focus: FocusTimer = FocusTimer(), at now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let start = calendar.startOfDay(for: now)
        var until = calendar.date(byAdding: .day, value: 8, to: start) ?? now.addingTimeInterval(7 * 86400)
        var dates: Set<Date> = [now]
        for offset in 1...7 {
            if let date = calendar.date(byAdding: .day, value: offset, to: start) { dates.insert(date) }
        }
        let counts = ReviewCounts(state: state, now: now, calendar: calendar)
        let dueDates = Set(counts.reviews + counts.fresh).filter { $0 > now && $0 < until }.sorted()
        for date in dueDates.prefix(48) { dates.insert(date) }
        // A bounded snapshot never presents a knowingly stale count after an
        // omitted event; the extension asks the user to reopen the app instead.
        if dueDates.count > 48 { until = dueDates[48] }
        let end = focus.completionDate(at: now)
        if let end, end > now, end < until { dates.insert(end) }
        var active = Set<String>(), minutes: [String: Double] = [:]
        for session in state.sessions {
            guard let completed = StudyEngine.parseTimestamp(session.completedAt), completed <= now,
                  session.durationMinutes.isFinite, session.durationMinutes >= 0 else { continue }
            let day = StudyEngine.localDate(completed, calendar: calendar)
            minutes[day, default: 0] += session.durationMinutes
            if StudyStreak.countsAsStudy(session) { active.insert(day) }
        }
        let moments = dates.filter { $0 < until }.sorted().map { date -> WidgetMoment in
            let today = StudyEngine.localDate(date, calendar: calendar)
            let reached = focus.isRunning && focus.remainingSeconds(at: date) <= 0
            return WidgetMoment(date: date, streak: StudyStreak.current(activeDays: active, at: date, calendar: calendar),
                studiedToday: active.contains(today), todayMinutes: minutes[today] ?? 0,
                goalMinutes: state.settings.dailyMinutes, dueReviews: counts.due(at: date, day: today),
                focusMinutes: focus.phase == .idle || focus.phase == .completed ? state.settings.focusMinutes : max(1, Int(ceil(focus.snapshot.targetSeconds / 60))), focusState: reached ? "ready" : focus.phase.rawValue,
                focusRemainingSeconds: focus.remainingSeconds(at: date), focusEndsAt: end.flatMap { $0 > date ? $0 : nil })
        }
        return WidgetSnapshot(generatedAt: now, validUntil: until, timeZoneIdentifier: calendar.timeZone.identifier, moments: moments)
    }

    private struct ReviewCounts {
        let reviews: [Date]
        let fresh: [Date]
        let newLimit: Int
        let firstByDay: [String: Int]
        init(state: AppState, now: Date, calendar: Calendar) {
            var reviewDates: [Date] = [], newDates: [Date] = [], firstDays: [String: Int] = [:], tracked = Set<String>()
            for session in state.sessions where session.kind == .review && session.id.hasPrefix("review:first:") {
                guard let completed = StudyEngine.parseTimestamp(session.completedAt), completed <= now else { continue }
                tracked.insert(String(session.id.dropFirst("review:first:".count)))
                firstDays[StudyEngine.localDate(completed, calendar: calendar), default: 0] += 1
            }
            for card in state.cards {
                if !tracked.contains(card.id), card.repetitions == 1, let last = card.lastReviewedAt.flatMap(StudyEngine.parseTimestamp), last <= now {
                    firstDays[StudyEngine.localDate(last, calendar: calendar), default: 0] += 1
                }
                guard !card.suspended, let due = StudyEngine.parseTimestamp(card.dueAt) else { continue }
                if card.lastReviewedAt != nil { reviewDates.append(due) } else { newDates.append(due) }
            }
            reviews = reviewDates.sorted(); fresh = newDates.sorted(); newLimit = state.settings.newCardsPerDay; firstByDay = firstDays
        }
        func due(at date: Date, day: String) -> Int {
            count(reviews, through: date) + min(count(fresh, through: date), max(0, newLimit - (firstByDay[day] ?? 0)))
        }
        private func count(_ values: [Date], through date: Date) -> Int {
            var lower = 0, upper = values.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if values[middle] <= date { lower = middle + 1 } else { upper = middle }
            }
            return lower
        }
    }
}
