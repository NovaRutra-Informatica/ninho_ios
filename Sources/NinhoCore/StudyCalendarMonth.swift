import Foundation

public struct StudyCalendarMonth: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        public let id: String
        public let number: Int
        public let studied: Bool
        public let isToday: Bool
        public let isFuture: Bool
    }
    public let start: Date
    public let leadingEmptyDays: Int
    public let days: [Day]
    public var studiedDays: Int { days.filter(\.studied).count }

    public init(containing date: Date, activeDays: Set<String>, at now: Date, calendar: Calendar = .current) {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        self.start = start
        leadingEmptyDays = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let today = calendar.startOfDay(for: now)
        days = (calendar.range(of: .day, in: .month, for: start) ?? 1..<1).compactMap { number in
            guard let value = calendar.date(byAdding: .day, value: number - 1, to: start) else { return nil }
            let key = StudyEngine.localDate(value, calendar: calendar)
            return Day(date: value, id: key, number: number,
                       studied: value <= today && activeDays.contains(key),
                       isToday: calendar.isDate(value, inSameDayAs: now), isFuture: value > today)
        }
    }
}
