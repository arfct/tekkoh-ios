import Foundation

/// What the widget knows about the journal: which of the last two weeks
/// have a page, and the run of days written. No words, places or photos:
/// those stay encrypted in the app. The app writes this to the shared app
/// group container on every save and sync; the widget only reads it.
struct Glance: Codable, Equatable {
    /// Days in a row ending at `runEnd`.
    var run: Int
    /// The last day of the run: today or yesterday when it was written, so
    /// the widget can tell, days later, whether the run is still alive.
    var runEnd: String?
    /// Days with a page among the last fourteen.
    var recent: [String]

    static let group = "group.com.artifact.tekkoh"
    private static let key = "glance"

    /// The streak as it stands on `today`: the run, if it reaches today or
    /// yesterday; otherwise it has ended.
    func streak(on today: String) -> Int {
        guard let end = runEnd, end == today || end == Day.add(-1, to: today) else { return 0 }
        return run
    }

    func written(_ day: String) -> Bool { recent.contains(day) }

    static func load() -> Glance? {
        guard let d = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Glance.self, from: d)
    }

    /// Stores it, and says whether anything changed.
    @discardableResult
    func save() -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.group), Self.load() != self,
              let d = try? JSONEncoder().encode(self) else { return false }
        defaults.set(d, forKey: Self.key)
        return true
    }

    static func clear() { UserDefaults(suiteName: group)?.removeObject(forKey: key) }
}
