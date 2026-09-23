import Foundation

/// External links navigate only. They never start a timer or mutate a study record.
public enum NativeStudyDestination: String, CaseIterable, Sendable {
    case today, focus, reviews, progress

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "ninho",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let host = parts.host?.lowercased(), let destination = Self(rawValue: host)
        else { return nil }
        self = destination
    }

    public var url: URL { URL(string: "ninho://\(rawValue)")! }
    public var tabIndex: Int {
        switch self { case .today, .progress: 0; case .focus: 2; case .reviews: 3 }
    }
}
