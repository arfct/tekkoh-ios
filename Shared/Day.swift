import Foundation

/// Days as yyyy-MM-dd keys in the phone's calendar. Shared with the widget.
enum Day {
    static let format: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String {
        format.timeZone = .current
        return format.string(from: d)
    }

    static func date(_ key: String) -> Date {
        format.timeZone = .current
        return format.date(from: key) ?? .now
    }

    static var today: String { key(.now) }

    static func add(_ n: Int, to key: String) -> String {
        Self.key(Calendar.current.date(byAdding: .day, value: n, to: date(key)) ?? .now)
    }

    /// The span of a day, for location and Health queries.
    static func interval(_ key: String) -> DateInterval {
        let start = Calendar.current.startOfDay(for: date(key))
        return DateInterval(start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start)
    }
}
