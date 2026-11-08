import CryptoKit
import Foundation
import Network
import Observation
import UIKit

/// The whole journal, kept on the phone so it reads and writes offline; the
/// server is the backup and the way between devices.
///
/// On disk every entry is the same sealed envelope the server holds, and
/// every photo the same sealed bytes, so nothing is ever written in the
/// clear. `state.json` keeps only ids, revisions and what's waiting to sync.
@MainActor @Observable
final class Journal {
    let identity: Keychain.Identity
    private(set) var entries: [String: Entry] = [:] // by day
    private(set) var syncing = false
    private(set) var lastSynced: Date?
    private(set) var syncError: String?
    private(set) var online = true

    @ObservationIgnored private let api: API
    @ObservationIgnored private let dir: URL
    @ObservationIgnored private var state = State()
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let thumbs = NSCache<NSString, UIImage>()
    /// Entry id to day, from the decrypted entries.
    @ObservationIgnored private var dayOf: [String: String] = [:]

    /// What sync needs about an entry. Which day it is lives only inside
    /// the encrypted entry, not in this file. (Older builds wrote `day`
    /// here; it's read and dropped.)
    struct Record: Codable {
        var day: String?
        var rev: Int = 0
        var dirty = false
    }

    struct State: Codable {
        var cursor: Int64 = 0
        var records: [String: Record] = [:] // by entry id
        var uploads: [String] = [] // photo blobs not yet on the server
        var removals: [String] = [] // photo blobs to delete there
    }

    init(identity: Keychain.Identity) {
        self.identity = identity
        api = API(identity: identity)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appending(path: "Tekkoh/\(identity.handle)")
        for sub in ["entries", "photos"] {
            try? FileManager.default.createDirectory(at: dir.appending(path: sub), withIntermediateDirectories: true)
        }
        // Readable after first unlock, like the key, so background work can sync.
        try? (dir as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
        load()
    }

    var key: SymmetricKey { identity.journalKey }
    var handle: String { identity.handle }

    func entry(_ day: String) -> Entry { entries[day] ?? Entry(day: day) }

    var pending: Int { state.records.values.filter(\.dirty).count + state.uploads.count }

    // MARK: Local files

    private var stateURL: URL { dir.appending(path: "state.json") }
    private func entryURL(_ id: String) -> URL { dir.appending(path: "entries/\(id).tek") }
    /// The last version this phone and the server agreed on, for merging.
    private func baseURL(_ id: String) -> URL { dir.appending(path: "entries/\(id).base") }

    private func base(_ id: String) -> Entry? {
        guard let d = try? Data(contentsOf: baseURL(id)), let plain = try? Crypto.openEntry(d, id: id, journal: key) else { return nil }
        return try? JSONDecoder.tekkoh.decode(Entry.self, from: plain)
    }

    private func setBase(_ id: String, _ sealed: Data) {
        try? sealed.write(to: baseURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func photoURL(_ id: String) -> URL { dir.appending(path: "photos/\(id).tek") }

    private func load() {
        if let d = try? Data(contentsOf: stateURL), let s = try? JSONDecoder().decode(State.self, from: d) { state = s }
        for id in state.records.keys {
            guard let sealed = try? Data(contentsOf: entryURL(id)),
                  let plain = try? Crypto.openEntry(sealed, id: id, journal: key),
                  let e = try? JSONDecoder.tekkoh.decode(Entry.self, from: plain) else { continue }
            entries[e.day] = e
            dayOf[id] = e.day
        }
        repairRepeats()
    }

    /// Once: collapse pages an early build repeated by merging them with
    /// their own earlier versions.
    private func repairRepeats() {
        let flag = "repairedRepeats.\(handle)"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        for e in entries.values {
            if let fixed = Entry.collapsingRepeats(e.text) {
                var n = e
                n.text = fixed
                save(n)
            }
        }
    }

    private func saveState() {
        var s = state
        for k in s.records.keys { s.records[k]?.day = nil }
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }

    private func write(_ e: Entry) throws -> Data {
        let id = Crypto.entryID(key, day: e.day)
        let sealed = try Crypto.sealEntry(try JSONEncoder.tekkoh.encode(e), id: id, journal: key)
        try sealed.write(to: entryURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return sealed
    }

    // MARK: Writing

    /// Saves a day's page on the phone and queues it for the server.
    func save(_ e: Entry) {
        var e = e
        guard entries[e.day] != e else { return }
        e.updated = .now
        if entries[e.day] == nil { e.created = .now }
        e.version = max(e.v, entries[e.day]?.v ?? 0) + 1
        entries[e.day] = e
        let id = Crypto.entryID(key, day: e.day)
        dayOf[id] = e.day
        do {
            _ = try write(e)
            var rec = state.records[id] ?? Record()
            rec.dirty = true
            state.records[id] = rec
            saveState()
        } catch {
            syncError = "Couldn't save on this phone: \(error.localizedDescription)"
        }
        Reminders.shared.refresh(self)
        schedulePush()
    }

    func update(_ day: String, _ change: (inout Entry) -> Void) {
        var e = entry(day)
        change(&e)
        save(e)
    }

    // MARK: Photos

    /// Adds a photo to a day: downsized, sealed with its own key, kept on
    /// the phone and queued for upload.
    func addPhoto(_ image: UIImage, to day: String, takenAt: Date?, asset: String?) throws {
        let img = image.downsized(maxSide: 2048)
        guard let jpeg = img.jpegData(compressionQuality: 0.82) else { return }
        let id = Crypto.randomID("p_")
        let pkey = SymmetricKey(size: .bits256)
        let sealed = try Crypto.seal(jpeg, key: pkey, context: "tekkoh/photo/\(id)")
        try sealed.write(to: photoURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state.uploads.append(id)
        saveState()
        let p = Photo(id: id, key: pkey.data, takenAt: takenAt, width: Int(img.size.width * img.scale), height: Int(img.size.height * img.scale), asset: asset)
        thumbs.setObject(img.downsized(maxSide: 900), forKey: id as NSString)
        update(day) { $0.photos.append(p) }
    }

    func removePhoto(_ p: Photo, from day: String) {
        update(day) { e in
            e.photos.removeAll { $0.id == p.id }
            if !e.removedPhotos.contains(p.id) { e.removedPhotos.append(p.id) }
        }
        try? FileManager.default.removeItem(at: photoURL(p.id))
        thumbs.removeObject(forKey: p.id as NSString)
        state.uploads.removeAll { $0 == p.id }
        state.removals.append(p.id)
        saveState()
    }

    func caption(_ p: Photo, in day: String, _ text: String) {
        update(day) { e in
            if let i = e.photos.firstIndex(where: { $0.id == p.id }) {
                e.photos[i].caption = text
                e.photos[i].updated = .now
            }
        }
    }

    func movePhoto(in day: String, from: Int, to: Int) {
        update(day) { e in
            guard e.photos.indices.contains(from), e.photos.indices.contains(to) else { return }
            e.photos.swapAt(from, to)
        }
    }

    /// The photo, decrypted: from memory, the phone, or the server.
    func image(_ p: Photo, full: Bool = false) async -> UIImage? {
        if !full, let t = thumbs.object(forKey: p.id as NSString) { return t }
        var sealed = try? Data(contentsOf: photoURL(p.id))
        if sealed == nil, let d = try? await api.blob(p.id) {
            try? d.write(to: photoURL(p.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            sealed = d
        }
        guard let sealed, let jpeg = try? Crypto.open(sealed, key: SymmetricKey(data: p.key), context: "tekkoh/photo/\(p.id)"),
              let img = UIImage(data: jpeg) else { return nil }
        let thumb = await Task.detached { img.downsized(maxSide: 900) }.value
        thumbs.setObject(thumb, forKey: p.id as NSString)
        return full ? img : thumb
    }

    // MARK: Sync

    func startMonitoring() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let was = self.online
                self.online = path.status == .satisfied
                if self.online && !was { await self.sync() }
            }
        }
        m.start(queue: .global(qos: .utility))
        monitor = m
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Photos up, the server's changes down (concatenating any day both
    /// sides changed), then this phone's changes up.
    func sync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await uploadPhotos()
            for _ in 0..<3 {
                try await pull()
                if try await push() { break }
            }
            try await removePhotos()
            lastSynced = .now
            syncError = nil
            Task { await self.prefetchPhotos() }
        } catch API.Failure.offline {
            syncError = nil // offline is normal; it'll sync when the network's back
        } catch {
            syncError = error.localizedDescription
        }
        Reminders.shared.refresh(self)
    }

    private func uploadPhotos() async throws {
        for id in state.uploads {
            guard let d = try? Data(contentsOf: photoURL(id)) else {
                state.uploads.removeAll { $0 == id }
                continue
            }
            try await api.put(blob: id, data: d)
            state.uploads.removeAll { $0 == id }
            saveState()
        }
    }

    private func removePhotos() async throws {
        for id in state.removals {
            do {
                try await api.delete(blob: id)
            } catch let API.Failure.status(code, _, _) where code == 404 {
                // Already gone.
            }
            // Anything else (offline, a server error) leaves it queued.
            state.removals.removeAll { $0 == id }
            saveState()
        }
    }

    private func pull() async throws {
        var more = true
        while more {
            let page = try await api.changes(after: state.cursor)
            for r in page.entries { apply(r) }
            state.cursor = page.cursor
            more = page.more
            saveState()
        }
    }

    private func apply(_ r: API.Remote) {
        let local = state.records[r.id]
        if r.deleted {
            // The app never deletes a page, so a deletion can only be forged:
            // keep ours and put it back.
            if var local, dayOf[r.id] != nil {
                local.rev = r.rev
                local.dirty = true
                state.records[r.id] = local
            }
            return
        }
        // This phone's own upload coming back, or older: nothing new.
        if let local, r.rev <= local.rev { return }
        guard let data = r.data, let plain = try? Crypto.openEntry(data, id: r.id, journal: key),
              let remote = try? JSONDecoder.tekkoh.decode(Entry.self, from: plain) else { return }
        // The id must be this day's: a server can't move a page to another date.
        guard Crypto.entryID(key, day: remote.day) == r.id else { return }
        dayOf[r.id] = remote.day
        if let local, local.dirty, let mine = entries[remote.day] {
            let merged = Entry.merge(remote, mine, base: base(r.id))
            entries[remote.day] = merged
            _ = try? write(merged)
            setBase(r.id, data)
            state.records[r.id] = Record(rev: r.rev, dirty: merged != remote)
        } else if let mine = entries[remote.day], remote.v < mine.v {
            // An older version than we have: a replay. Keep ours and put it back.
            state.records[r.id] = Record(rev: r.rev, dirty: true)
        } else {
            setBase(r.id, data)
            entries[remote.day] = remote
            try? data.write(to: entryURL(r.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            state.records[r.id] = Record(rev: r.rev, dirty: false)
        }
    }

    /// True when everything went up; false when the server had something
    /// newer (pull again, merge, retry).
    private func push() async throws -> Bool {
        for (id, rec) in state.records where rec.dirty {
            guard let sealed = try? Data(contentsOf: entryURL(id)) else { continue }
            do {
                let res = try await api.put(entry: id, data: sealed, rev: rec.rev)
                state.records[id]?.rev = res.rev
                setBase(id, sealed)
                // Still dirty if it changed again while uploading.
                if let now = try? Data(contentsOf: entryURL(id)), now == sealed { state.records[id]?.dirty = false }
                saveState()
            } catch let API.Failure.status(code, _, _) where code == 409 {
                return false
            }
        }
        return true
    }

    /// Every photo on the phone, so the journal reads offline.
    private func prefetchPhotos() async {
        for e in entries.values {
            for p in e.photos where !FileManager.default.fileExists(atPath: photoURL(p.id).path) {
                if let d = try? await api.blob(p.id) {
                    try? d.write(to: photoURL(p.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            }
        }
    }

    // MARK: Streaks

    var writtenDays: Set<String> { Set(entries.values.filter(\.hasContent).map(\.day)) }

    /// Days in a row up to today (or yesterday, if today isn't written yet).
    var streak: Int { Streak.current(writtenDays, today: Day.today) }
    var longestStreak: Int { Streak.longest(writtenDays) }
    var writtenToday: Bool { entries[Day.today]?.hasContent ?? false }

    // MARK: Leaving

    /// Removes the journal from this phone. The key stays in iCloud
    /// Keychain: deleting it there would delete it from every device.
    func signOut() {
        monitor?.cancel()
        try? FileManager.default.removeItem(at: dir)
        Reminders.shared.clear()
    }

    /// Deletes the journal on the server and here, and the key everywhere.
    func deleteEverywhere() async throws {
        try await api.deleteAccount()
        signOut()
        Keychain.delete()
    }

    /// Whether the server still holds a PIN recovery for this journal
    /// (ten wrong PINs remove it); nil if it can't be reached.
    func recoveryActive() async -> Bool? {
        (try? await api.me())?["recovery"] as? Bool
    }

    func changePIN(_ pin: String) async throws {
        try await api.setPIN(pin, journal: key)
    }
}

extension UIImage {
    func downsized(maxSide: CGFloat) -> UIImage {
        let w = size.width * scale, h = size.height * scale
        let k = min(1, maxSide / max(w, h))
        if k >= 1 { return self }
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w * k, height: h * k), format: fmt).image { _ in
            draw(in: CGRect(x: 0, y: 0, width: w * k, height: h * k))
        }
    }
}
