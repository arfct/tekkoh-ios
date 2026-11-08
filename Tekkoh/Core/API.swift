import CryptoKit
import Foundation

/// The Tekkoh server: it only ever sees ciphertext.
struct API {
    static let base = URL(string: "https://tekkoh.cronbon.com")!

    enum Failure: LocalizedError {
        case offline
        case status(Int, String, [String: Any])

        var errorDescription: String? {
            switch self {
            case .offline: return "Can't reach Tekkoh's server."
            case .status(_, let msg, _): return msg
            }
        }

        var code: Int? { if case .status(let c, _, _) = self { return c }; return nil }
    }

    var handle: String?
    var token: Data?

    init(identity: Keychain.Identity? = nil) {
        if let identity {
            handle = identity.handle
            token = Crypto.authToken(identity.journalKey)
        }
    }

    private func request(_ method: String, _ path: String, json: Any? = nil, body: Data? = nil) async throws -> (Data, Int) {
        var r = URLRequest(url: URL(string: path, relativeTo: Self.base)!)
        r.httpMethod = method
        r.timeoutInterval = 30
        if let handle, let token {
            r.setValue("Tekkoh \(handle) \(token.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        if let json {
            r.httpBody = try JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            r.httpBody = body
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: r)
        } catch {
            throw Failure.offline
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw Failure.status(code, obj["error"] as? String ?? "The server said \(code).", obj)
        }
        return (data, code)
    }

    private func object(_ method: String, _ path: String, json: Any? = nil) async throws -> [String: Any] {
        let (d, _) = try await request(method, path, json: json)
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    // MARK: Accounts and recovery

    /// The PIN's verifier and the PIN-locked key, which must only ever
    /// travel inside a box to the server (either is enough to try every PIN).
    static func recoveryFields(journal: SymmetricKey, pin: String, handle: String) throws -> [String: Any] {
        let salt = Crypto.randomBytes(16)
        let p = Crypto.stretch(pin: pin, salt: salt)
        return [
            "salt": salt.base64EncodedString(),
            "iterations": Crypto.pinIterations,
            "verifier": p.verifier.base64EncodedString(),
            "blob": try Crypto.lock(journal: journal, with: p, handle: handle).base64EncodedString(),
        ]
    }

    func createAccount(handle: String, journal: SymmetricKey, pin: String) async throws {
        let box = try Transport.seal(try Self.recoveryFields(journal: journal, pin: pin, handle: handle), purpose: "create")
        _ = try await object("POST", "/v1/accounts", json: [
            "handle": handle,
            "auth": Crypto.authToken(journal).base64EncodedString(),
            "recovery": box.body,
        ])
    }

    func setPIN(_ pin: String, journal: SymmetricKey) async throws {
        let box = try Transport.seal(try Self.recoveryFields(journal: journal, pin: pin, handle: handle ?? ""), purpose: "set-recovery")
        _ = try await object("PUT", "/v1/recovery", json: box.body)
    }

    struct RecoveryParams {
        let salt: Data
        let iterations: Int
        let attemptsLeft: Int
    }

    func recoveryParams(handle: String) async throws -> RecoveryParams {
        // In the body, not the URL, so the username stays out of access logs.
        let o = try await object("POST", "/v1/recovery/params", json: ["handle": handle])
        let p = RecoveryParams(salt: Data(base64Encoded: o["salt"] as? String ?? "") ?? Data(),
                               iterations: o["iterations"] as? Int ?? 0,
                               attemptsLeft: o["attemptsLeft"] as? Int ?? 0)
        // Don't let a server talk the phone into weak stretching.
        guard p.salt.count >= 16, p.iterations >= Crypto.pinIterations, p.iterations <= 20_000_000 else {
            throw Failure.status(0, "The server asked for unsafe PIN settings.", [:])
        }
        return p
    }

    /// The locked journal key, for the right PIN's verifier. Both travel
    /// boxed to the server's key.
    func recover(handle: String, verifier: Data) async throws -> Data {
        let box = try Transport.seal(["verifier": verifier.base64EncodedString()], purpose: "recover")
        let o = try await object("POST", "/v1/recovery", json: ["handle": handle, "proof": box.body])
        guard let reply = (o["reply"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let blob = (try box.open(reply)["blob"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
            throw Failure.status(0, "The server's reply didn't open.", [:])
        }
        return blob
    }

    func me() async throws -> [String: Any] { try await object("GET", "/v1/me") }

    // MARK: Linked browsers

    /// Puts the journal key, sealed to a browser, in the slot its QR code named.
    func link(slot: String, box: Data) async throws {
        _ = try await object("PUT", "/v1/pair/\(slot)", json: ["box": box.base64EncodedString()])
    }

    struct Browser: Identifiable {
        let id: String
        let label: String
        var agent = false
        let created: Date?
        let lastUsed: Date?
    }

    func browsers() async throws -> [Browser] {
        let o = try await object("GET", "/v1/sessions")
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ v: Any?) -> Date? { (v as? String).flatMap { f.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } }
        return (o["sessions"] as? [[String: Any]] ?? []).map {
            Browser(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "A browser", agent: $0["kind"] as? String == "agent",
                    created: date($0["createdAt"]), lastUsed: date($0["lastUsed"]))
        }
    }

    func unlink(browser id: String) async throws { _ = try await object("DELETE", "/v1/sessions/\(id)") }
    func deleteAccount() async throws { _ = try await object("DELETE", "/v1/me") }

    // MARK: Entries

    struct Remote {
        let id: String
        let data: Data?
        let rev: Int
        let seq: Int64
        let deleted: Bool
    }

    func changes(after: Int64) async throws -> (entries: [Remote], cursor: Int64, more: Bool) {
        let o = try await object("GET", "/v1/entries?after=\(after)")
        let list = (o["entries"] as? [[String: Any]] ?? []).map { e in
            Remote(id: e["id"] as? String ?? "", data: (e["data"] as? String).flatMap { Data(base64Encoded: $0) },
                   rev: e["rev"] as? Int ?? 0, seq: (e["seq"] as? NSNumber)?.int64Value ?? 0, deleted: e["deleted"] as? Bool ?? false)
        }
        return (list, (o["cursor"] as? NSNumber)?.int64Value ?? after, o["more"] as? Bool ?? false)
    }

    /// Stores an entry at rev+1; throws a 409 if it changed elsewhere.
    func put(entry id: String, data: Data, rev: Int) async throws -> (rev: Int, seq: Int64) {
        let o = try await object("PUT", "/v1/entries/\(id)", json: ["data": data.base64EncodedString(), "rev": rev])
        return (o["rev"] as? Int ?? rev + 1, (o["seq"] as? NSNumber)?.int64Value ?? 0)
    }

    func put(blob id: String, data: Data) async throws { _ = try await request("PUT", "/v1/blobs/\(id)", body: data) }
    func blob(_ id: String) async throws -> Data { try await request("GET", "/v1/blobs/\(id)").0 }
    func delete(blob id: String) async throws { _ = try await request("DELETE", "/v1/blobs/\(id)") }
}
