import Foundation

/// One day's page. Encrypted as a whole: the server sees only ciphertext.
struct Entry: Codable, Equatable, Identifiable {
    var day: String // yyyy-MM-dd, in the writer's calendar
    var text: String = ""
    var photos: [Photo] = []
    /// Photos removed from the page, so a sync from another device doesn't
    /// bring them back.
    var removedPhotos: [String] = []
    var places: [Place] = []
    var health: Health?
    var sun: Sun?
    var created: Date = .now
    var updated: Date = .now
    /// Counts up with every save, inside the encryption, so a server can't
    /// hand back an older version of a page as if it were current.
    var version: Int?

    var id: String { day }
    var v: Int { version ?? 0 }

    /// What counts toward the streak: some words or a photo.
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty
    }

    static let divider = "\n\n· · ·\n\n"

    /// Undoes the repeats an early build made by concatenating a page with
    /// its own earlier versions: when every part starts the same way, they
    /// were one page, and the longest part is kept. Two devices' genuinely
    /// different words are left alone.
    static func collapsingRepeats(_ text: String) -> String? {
        let parts = text.components(separatedBy: divider.trimmingCharacters(in: .newlines)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        let head = String(parts[0].prefix(24))
        guard head.count >= 12, parts.allSatisfy({ $0.hasPrefix(head) }) else { return nil }
        return parts.max { $0.count < $1.count }
    }

    /// Two versions of a day, given the last version both sides had
    /// (`base`). Only when both changed the words since then are they put
    /// one after the other; if just one side changed, that side's words
    /// stand. Photos and places are combined either way.
    static func merge(_ remote: Entry, _ local: Entry, base: Entry?) -> Entry {
        var m = merge(remote, local)
        if let base {
            if remote.text == base.text { m.text = local.text } else if local.text == base.text { m.text = remote.text }
        }
        return m
    }

    /// Two versions of the same day from different devices. The words are
    /// put one after the other rather than merged; photos and places are
    /// combined; the newer activity reading wins.
    static func merge(_ remote: Entry, _ local: Entry) -> Entry {
        if remote == local { return local }
        var out = local
        let r = remote.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = local.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty || l.hasPrefix(r) {
            out.text = local.text
        } else if l.isEmpty || r.hasPrefix(l) {
            out.text = remote.text
        } else if r.contains(l) {
            out.text = remote.text
        } else if l.contains(r) {
            out.text = local.text
        } else {
            out.text = r + divider + l
        }
        let removed = Set(remote.removedPhotos).union(local.removedPhotos)
        out.removedPhotos = Array(removed).sorted()
        var photos: [String: Photo] = [:]
        var order: [String] = []
        for p in remote.photos + local.photos where !removed.contains(p.id) {
            if let cur = photos[p.id] {
                if p.updated > cur.updated { photos[p.id] = p }
            } else {
                photos[p.id] = p
                order.append(p.id)
            }
        }
        out.photos = order.compactMap { photos[$0] }
        out.places = Place.combine(remote.places, local.places)
        switch (remote.health, local.health) {
        case let (r?, l?): out.health = r.asOf > l.asOf ? r : l
        case let (r?, nil): out.health = r
        default: break
        }
        out.sun = local.sun ?? remote.sun
        out.created = min(remote.created, local.created)
        out.updated = max(remote.updated, local.updated, .now)
        out.version = max(remote.v, local.v) + 1
        return out
    }
}

struct Photo: Codable, Equatable, Identifiable, Hashable {
    var id: String // the blob's id on the server
    var key: Data // the photo's own AES key
    var caption: String = ""
    var takenAt: Date?
    var width: Int
    var height: Int
    /// The Photos library item it came from, so it isn't suggested twice.
    var asset: String?
    var updated: Date = .now

    var aspect: CGFloat { height > 0 ? CGFloat(width) / CGFloat(height) : 1 }
}

struct Place: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var detail: String = ""
    var lat: Double
    var lon: Double
    var arrived: Date?
    var departed: Date?

    /// Places from two lists, the same spot counted once.
    static func combine(_ a: [Place], _ b: [Place]) -> [Place] {
        var out: [Place] = []
        for p in a + b {
            if let i = out.firstIndex(where: { $0.id == p.id || ($0.name == p.name && $0.distance(to: p) < 300) }) {
                out[i].arrived = [out[i].arrived, p.arrived].compactMap { $0 }.min()
                out[i].departed = [out[i].departed, p.departed].compactMap { $0 }.max()
            } else {
                out.append(p)
            }
        }
        return out.sorted { ($0.arrived ?? .distantFuture) < ($1.arrived ?? .distantFuture) }
    }

    func distance(to p: Place) -> Double {
        let r = 6_371_000.0
        let dLat = (p.lat - lat) * .pi / 180, dLon = (p.lon - lon) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat * .pi / 180) * cos(p.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

struct Health: Codable, Equatable {
    var steps: Int?
    var meters: Double?
    var flights: Int?
    var activeKcal: Double?
    var exerciseMinutes: Double?
    var workouts: [Workout] = []
    var asOf: Date = .now

    var isEmpty: Bool { (steps ?? 0) == 0 && (meters ?? 0) == 0 && workouts.isEmpty }
}

struct Workout: Codable, Equatable, Hashable {
    var kind: String
    var minutes: Double
    var kcal: Double?
    var meters: Double?
}

struct Sun: Codable, Equatable {
    var rise: Date?
    var set: Date?
}

// MARK: - Days

/// PINs anyone would try first. With ten tries, these are the ones that
/// would fall, so they aren't allowed.
enum PINPolicy {
    static let common: Set<String> = [
        "123123", "112233", "121212", "131313", "101010", "123321", "147258", "258369", "159357", "159753",
        "147852", "789456", "456123", "963852", "741852", "852963", "102030", "520520", "696969", "100200",
        "121314", "112211", "987654", "456789", "012345", "098765", "135790", "246810", "111222", "123654",
    ]

    /// Why a PIN is too easy to guess, or nil if it's fine.
    static func problem(_ pin: String) -> String? {
        let d = pin.compactMap(\.wholeNumberValue)
        guard d.count == 6 else { return "Six digits." }
        if Set(d).count == 1 { return "Not one digit six times." }
        let steps = zip(d, d.dropFirst()).map { ($1 - $0 + 10) % 10 }
        if Set(steps).count == 1 && (steps[0] == 1 || steps[0] == 9) { return "Not a run of digits." }
        if d[0..<2] == d[2..<4] && d[2..<4] == d[4..<6] { return "Not one pair three times." }
        if d[0..<3] == d[3..<6] { return "Not the same three twice." }
        if d == d.reversed() { return "Not the same both ways." }
        if Set(d).count <= 2 { return "Use more than two different digits." }
        if common.contains(pin) { return "That's one of the first PINs anyone would try." }
        return nil
    }
}

enum Streak {
    static func current(_ days: Set<String>, today: String) -> Int {
        var d = days.contains(today) ? today : Day.add(-1, to: today)
        var n = 0
        while days.contains(d) {
            n += 1
            d = Day.add(-1, to: d)
        }
        return n
    }

    static func longest(_ days: Set<String>) -> Int {
        var best = 0
        for d in days where !days.contains(Day.add(-1, to: d)) {
            var n = 1, cur = d
            while days.contains(Day.add(1, to: cur)) { n += 1; cur = Day.add(1, to: cur) }
            best = max(best, n)
        }
        return best
    }
}

extension JSONEncoder {
    static let tekkoh: JSONEncoder = {
        // Dates as seconds since the reference date, which round-trips
        // exactly, so an entry read back compares equal to the one written.
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()
}

extension JSONDecoder {
    static let tekkoh: JSONDecoder = {
        JSONDecoder()
    }()
}
