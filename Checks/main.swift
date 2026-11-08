import CryptoKit
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "ok   " : "FAIL ", what); if !ok { failures += 1 } }

// Crypto: entries round-trip, bind to their id, and fail with another key.
let key = SymmetricKey(size: .bits256)
let id = Crypto.entryID(key, day: "2026-11-07")
check(id.count == 32 && id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil, "entry id is 32 url-safe chars: \(id)")
check(Crypto.entryID(key, day: "2026-11-07") == id && Crypto.entryID(key, day: "2026-11-08") != id, "entry ids are stable per day, different across days")
check(Crypto.entryID(SymmetricKey(size: .bits256), day: "2026-11-07") != id, "entry id depends on the key")
let entry = Entry(day: "2026-11-07", text: "Walked to the ferry building.")
let plain = try! JSONEncoder.tekkoh.encode(entry)
let sealed = try! Crypto.sealEntry(plain, id: id, journal: key)
check(!String(decoding: sealed, as: UTF8.self).contains("ferry"), "sealed entry hides the text")
let back = try! JSONDecoder.tekkoh.decode(Entry.self, from: try! Crypto.openEntry(sealed, id: id, journal: key))
check(back == entry, "entry round-trips exactly (dates too)")
check((try? Crypto.openEntry(sealed, id: id, journal: SymmetricKey(size: .bits256))) == nil, "another key can't open it")
check((try? Crypto.openEntry(sealed, id: Crypto.entryID(key, day: "2026-11-08"), journal: key)) == nil, "it can't be moved to another day's id")

// PIN stretching: deterministic, different PINs differ, lock/unlock.
let salt = Crypto.randomBytes(16)
let t = Date()
let a = Crypto.stretch(pin: "246810", salt: salt)
let ms = Int(Date().timeIntervalSince(t) * 1000)
check(a.verifier == Crypto.stretch(pin: "246810", salt: salt).verifier, "stretch is deterministic (\(ms) ms on this Mac)")
check(a.verifier != Crypto.stretch(pin: "246811", salt: salt).verifier, "a different PIN gives a different verifier")
check(a.verifier != a.wrapKey.data, "verifier and wrapping key differ")
let blob = try! Crypto.lock(journal: key, with: a, handle: "kiko")
check(blob.count == 60, "locked key is 60 bytes (server accepts 32-512)")
check((try? Crypto.unlock(blob, with: a, handle: "kiko"))?.data == key.data, "right PIN unlocks the key")
check((try? Crypto.unlock(blob, with: Crypto.stretch(pin: "000000", salt: salt), handle: "kiko")) == nil, "wrong PIN doesn't")

// Merge: concatenate different words, combine photos, honour removals.
var r = Entry(day: "2026-11-07", text: "Morning: coffee with Ana.")
var l = Entry(day: "2026-11-07", text: "Evening: long walk home.")
let p1 = Photo(id: "p_1", key: Data(count: 32), width: 10, height: 10)
let p2 = Photo(id: "p_2", key: Data(count: 32), width: 10, height: 10)
let p3 = Photo(id: "p_3", key: Data(count: 32), width: 10, height: 10)
r.photos = [p1, p2]; l.photos = [p3]; l.removedPhotos = ["p_2"]
let m = Entry.merge(r, l)
check(m.text == "Morning: coffee with Ana." + Entry.divider + "Evening: long walk home.", "different words are concatenated")
check(m.photos.map(\.id) == ["p_1", "p_3"], "photos combined, the removed one stays removed")
var grown = r; grown.text = r.text + " Then the market."
check(Entry.merge(r, grown).text == grown.text, "an edit that extends the other keeps the longer, no duplicate")
check(Entry.merge(grown, r).text == grown.text, "…in either direction")
check(Entry.merge(Entry(day: "x"), l).text == l.text, "empty side takes the other")
let mm = Entry.merge(m, l)
check(mm.text == m.text, "merging again doesn't repeat text")

// Agents' notes: as the command-line tool writes them, and merged by agent.
let cliJSON = #"{"agentNotes":[{"agent":"Morning agent","id":"s1","text":"Booked the dentist.","updated":815817800.5}],"created":815817713.7,"day":"2026-11-08","photos":[],"places":[],"removedPhotos":[],"text":"Rain.","updated":815817800.5,"version":3}"#
let fromCLI = try? JSONDecoder.tekkoh.decode(Entry.self, from: Data(cliJSON.utf8))
check(fromCLI?.notes.first?.text == "Booked the dentist." && fromCLI?.text == "Rain.", "reads a page with an agent's note, as the CLI writes it")
let oldJSON = #"{"created":815817713.7,"day":"2026-11-08","photos":[],"places":[],"removedPhotos":[],"text":"Rain.","updated":815817800.5}"#
check((try? JSONDecoder.tekkoh.decode(Entry.self, from: Data(oldJSON.utf8)))?.agentNotes == nil, "still reads a page from before agents")
var na = Entry(day: "2026-11-08"), nb = na
na.agentNotes = [AgentNote(id: "s1", agent: "A", text: "old", updated: Date(timeIntervalSinceReferenceDate: 1)), AgentNote(id: "s2", agent: "B", text: "b", updated: Date(timeIntervalSinceReferenceDate: 1))]
nb.agentNotes = [AgentNote(id: "s1", agent: "A", text: "new", updated: Date(timeIntervalSinceReferenceDate: 2))]
let nm = Entry.merge(na, nb)
check(nm.notes.map(\.text) == ["new", "b"], "agents' notes merge one per agent, the newer edit winning")
check(Linking.parse("tekkoh-link:1:abcdefghijklmnopqrstuv:ja_P7q6QRe6aeNeKmfzzLneB5EHrBzCWw0K44tzDthI:agent")?.agent == true, "an agent's link code parses as an agent")
check(Linking.parse("tekkoh-link:1:abcdefghijklmnopqrstuv:ja_P7q6QRe6aeNeKmfzzLneB5EHrBzCWw0K44tzDthI")?.agent == false, "a browser's as a browser")
check(Linking.parse("tekkoh-link:1:abcdefghijklmnopqrstuv:ja_P7q6QRe6aeNeKmfzzLneB5EHrBzCWw0K44tzDthI:robot") == nil, "and nothing else")

// The repeat bug: this phone's own earlier version must not be concatenated.
let v1 = Entry(day: "2026-11-07", text: "Walked along the river to the old mill")
var v2 = v1; v2.text = "Walked along the river to the old harbour"
check(Entry.merge(v1, v2, base: v1).text == v2.text, "only this phone changed since the last sync: its words stand")
check(Entry.merge(v2, v1, base: v1).text == v2.text, "only the other side changed: theirs stand")
var other = v1; other.text = "A different device's page."
check(Entry.merge(other, v2, base: v1).text == other.text + Entry.divider + v2.text, "both changed since: concatenated")
let repeated = v1.text + Entry.divider + v2.text + Entry.divider + v2.text + " Then dinner."
check(Entry.collapsingRepeats(repeated) == v2.text + " Then dinner.", "repeats from the bug collapse to the fullest version")
check(Entry.collapsingRepeats(m.text) == nil, "two devices' different words are left alone")

// Obvious PINs are refused; ordinary ones aren't.
for weak in ["111111", "123456", "654321", "890123", "121212", "123123", "123321", "112112", "147258", "135790"] {
    check(PINPolicy.problem(weak) != nil, "refuses \(weak)")
}
for fine in ["374912", "508263", "961407"] {
    check(PINPolicy.problem(fine) == nil, "allows \(fine)")
}

// Versions only go up, so an older copy can be recognised.
let older = Entry(day: "2026-11-07", text: "a", version: 3)
var newer = older; newer.text = "ab"; newer.version = 5
check(Entry.merge(older, newer).v == 6, "a merge is newer than both sides")
check(older.v < newer.v, "a replayed older page has a lower version")

// Streaks.
let days: Set<String> = ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-10-01", "2026-10-02"]
check(Streak.current(days, today: "2026-11-07") == 4, "streak counts back from yesterday when today's blank")
check(Streak.current(days.union(["2026-11-07"]), today: "2026-11-07") == 5, "and includes today once written")
check(Streak.current(days, today: "2026-11-09") == 0, "a missed day ends it")
check(Streak.longest(days) == 4, "longest streak")

// Sun: San Francisco, 7 Nov 2026: sunrise ~6:41 PST, sunset ~17:03 PST.
TimeZone.ReferenceType.default = TimeZone(identifier: "America/Los_Angeles")!
let sun = SunTimes.compute(day: "2026-11-07", lat: 37.7749, lon: -122.4194)
let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/Los_Angeles"); f.dateFormat = "HH:mm"
print("     sun:", sun.rise.map(f.string) ?? "-", sun.set.map(f.string) ?? "-")
check(sun.rise.map(f.string)?.hasPrefix("06:4") == true && sun.set.map(f.string)?.hasPrefix("17:0") == true, "sunrise and sunset about right")

// Live server: create, recover with a wrong then right PIN, sync an entry, delete.
let sem = DispatchSemaphore(value: 0)
Task {
    let handle = "test" + Crypto.randomID("").prefix(8).lowercased().replacingOccurrences(of: "-", with: "a").replacingOccurrences(of: "_", with: "b")
    let jk = SymmetricKey(size: .bits256)
    do {
        try await API().createAccount(handle: handle, journal: jk, pin: "135790")
        check(true, "created \(handle) on the live server")
        let params = try await API().recoveryParams(handle: handle)
        check(params.iterations == Crypto.pinIterations && params.attemptsLeft == 10, "recovery params")
        do {
            _ = try await API().recover(handle: handle, verifier: Crypto.stretch(pin: "000000", salt: params.salt).verifier)
            check(false, "wrong PIN rejected")
        } catch let API.Failure.status(code, _, o) {
            check(code == 403 && (o["attemptsLeft"] as? Int) == 9, "wrong PIN rejected, 9 left")
        }
        let d = Crypto.stretch(pin: "135790", salt: params.salt, iterations: params.iterations)
        let got = try Crypto.unlock(try await API().recover(handle: handle, verifier: d.verifier), with: d, handle: handle)
        check(got.data == jk.data, "right PIN brings back the same journal key")
        let api = API(identity: Keychain.Identity(handle: handle, key: jk.data))
        let eid = Crypto.entryID(jk, day: "2026-11-07")
        let env = try Crypto.sealEntry(try JSONEncoder.tekkoh.encode(entry), id: eid, journal: jk)
        let put = try await api.put(entry: eid, data: env, rev: 0)
        check(put.rev == 1, "entry stored at rev 1")
        let ch = try await api.changes(after: 0)
        let remote = try JSONDecoder.tekkoh.decode(Entry.self, from: try Crypto.openEntry(ch.entries[0].data!, id: eid, journal: jk))
        check(remote == entry, "entry comes back and decrypts")
        do { _ = try await api.put(entry: eid, data: env, rev: 0); check(false, "stale write rejected") }
        catch let API.Failure.status(code, _, _) { check(code == 409, "stale write rejected with 409") }
        try await api.deleteAccount()
        check(true, "deleted the test account")
    } catch {
        check(false, "live server: \(error)")
    }
    sem.signal()
}
sem.wait()
print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
