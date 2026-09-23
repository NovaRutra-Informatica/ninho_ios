import Foundation

/// Only derived counts cross the app/extension boundary. No profile, materials,
/// card text, model, subject/session identifiers or navigation history is shared.
public struct WidgetMoment: Codable, Equatable, Sendable {
    public var date: Date
    public var streak: Int
    public var studiedToday: Bool
    public var todayMinutes: Double
    public var goalMinutes: Int
    public var dueReviews: Int
    public var focusMinutes: Int
    public var focusState: String
    public var focusRemainingSeconds: Double
    public var focusEndsAt: Date?
    public init(date: Date, streak: Int = 0, studiedToday: Bool = false, todayMinutes: Double = 0,
                goalMinutes: Int = 30, dueReviews: Int = 0, focusMinutes: Int = 25,
                focusState: String = "idle", focusRemainingSeconds: Double = 0, focusEndsAt: Date? = nil) {
        self.date = date; self.streak = streak; self.studiedToday = studiedToday
        self.todayMinutes = todayMinutes; self.goalMinutes = goalMinutes; self.dueReviews = dueReviews
        self.focusMinutes = focusMinutes; self.focusState = focusState
        self.focusRemainingSeconds = focusRemainingSeconds; self.focusEndsAt = focusEndsAt
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let version = 1
    public var schema: Int = Self.version
    public var generatedAt: Date
    public var validUntil: Date
    public var timeZoneIdentifier: String
    public var moments: [WidgetMoment]
    public init(generatedAt: Date, validUntil: Date, timeZoneIdentifier: String, moments: [WidgetMoment]) {
        self.generatedAt = generatedAt; self.validUntil = validUntil
        self.timeZoneIdentifier = timeZoneIdentifier; self.moments = moments
    }
    public func validate() throws {
        guard schema == Self.version, generatedAt.timeIntervalSince1970.isFinite,
              validUntil > generatedAt, validUntil.timeIntervalSince(generatedAt) <= 9 * 86400,
              TimeZone(identifier: timeZoneIdentifier) != nil, (1...64).contains(moments.count),
              moments.first?.date == generatedAt else { throw WidgetSnapshotError.invalid }
        var previous = Date.distantPast
        for value in moments {
            guard value.date >= generatedAt, value.date < validUntil, value.date > previous,
                  (0...1_000_000).contains(value.streak), (0...1_000_000).contains(value.dueReviews),
                  value.todayMinutes.isFinite, (0...1_000_000).contains(value.todayMinutes),
                  (1...1440).contains(value.goalMinutes), (1...1440).contains(value.focusMinutes),
                  ["idle", "running", "paused", "completed", "ready"].contains(value.focusState),
                  value.focusRemainingSeconds.isFinite, (0...86400).contains(value.focusRemainingSeconds),
                  value.focusEndsAt.map({ $0 > value.date && $0.timeIntervalSince(value.date) <= 86400 }) ?? true
            else { throw WidgetSnapshotError.invalid }
            previous = value.date
        }
    }
    /// A timezone change requires new app aggregation; never keep yesterday's
    /// goal or streak indefinitely if WidgetKit delays a reload.
    public func moment(at now: Date, timeZone: TimeZone = .current) -> WidgetMoment? {
        guard (try? validate()) != nil, now >= generatedAt, now < validUntil,
              timeZoneIdentifier == timeZone.identifier else { return nil }
        return moments.last { $0.date <= now }
    }
}

public enum WidgetSnapshotError: Error { case invalid, tooLarge, unavailable }

public enum WidgetSnapshotFile {
    public static let name = "widget-summary-v1.json"
    public static let maximumBytes = 65_536
    public static func read(in directory: URL) throws -> WidgetSnapshot {
        let url = directory.appendingPathComponent(name)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw WidgetSnapshotError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw WidgetSnapshotError.tooLarge }
        let result = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        try result.validate(); return result
    }
    public static func write(_ snapshot: WidgetSnapshot, in directory: URL) throws {
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumBytes else { throw WidgetSnapshotError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: destination, options: .atomic)
        #endif
        var file = destination
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
}
