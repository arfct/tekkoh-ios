import CommonCrypto
import CryptoKit
import Foundation

/// Everything secret about a journal comes from one random 256-bit journal
/// key. It lives in the Keychain (synced by iCloud Keychain to the person's
/// own devices) and, locked with their PIN, on the server for recovery.
///
/// - Entries: each has its own random key; the entry's JSON is sealed with
///   it (AES-GCM) and the entry key is sealed with the journal key.
/// - Photos: each has its own random key, kept inside its (encrypted) entry.
/// - Entry ids: a keyed hash of the day, so ids don't show dates (when a
///   page is first uploaded still roughly does).
/// - Signing in: a token derived from the journal key; the server keeps its
///   hash and learns nothing about the key.
/// - The PIN: stretched with PBKDF2 into a verifier (sent to the server) and
///   a wrapping key (which locks the journal key and never leaves the phone).
enum Crypto {
    static let pinIterations = 600_000

    // MARK: Derived keys

    static func derive(_ key: SymmetricKey, _ info: String, bytes: Int = 32) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data(info.utf8), outputByteCount: bytes)
    }

    /// The token that signs this journal's requests.
    static func authToken(_ journal: SymmetricKey) -> Data {
        derive(journal, "tekkoh/auth/v1").data
    }

    /// The server-side id of a day's entry.
    static func entryID(_ journal: SymmetricKey, day: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("day:\(day)".utf8), using: derive(journal, "tekkoh/entry-id/v1"))
        return Data(mac).prefix(24).base64URL
    }

    static func randomID(_ prefix: String) -> String {
        prefix + SymmetricKey(size: .bits128).data.base64URL
    }

    // MARK: Entries

    struct Envelope: Codable {
        var v = 1
        /// The entry key, sealed with the journal key.
        var k: Data
        /// The entry's JSON, sealed with the entry key.
        var c: Data
    }

    static func sealEntry(_ plaintext: Data, id: String, journal: SymmetricKey) throws -> Data {
        let entryKey = SymmetricKey(size: .bits256)
        let k = try AES.GCM.seal(entryKey.data, using: journal, authenticating: Data("tekkoh/entry-key/\(id)".utf8)).combined!
        let c = try AES.GCM.seal(plaintext, using: entryKey, authenticating: Data("tekkoh/entry/\(id)".utf8)).combined!
        return try JSONEncoder().encode(Envelope(k: k, c: c))
    }

    static func openEntry(_ sealed: Data, id: String, journal: SymmetricKey) throws -> Data {
        let env = try JSONDecoder().decode(Envelope.self, from: sealed)
        let keyData = try AES.GCM.open(AES.GCM.SealedBox(combined: env.k), using: journal, authenticating: Data("tekkoh/entry-key/\(id)".utf8))
        return try AES.GCM.open(AES.GCM.SealedBox(combined: env.c), using: SymmetricKey(data: keyData), authenticating: Data("tekkoh/entry/\(id)".utf8))
    }

    // MARK: Photos and local files

    static func seal(_ data: Data, key: SymmetricKey, context: String) throws -> Data {
        try AES.GCM.seal(data, using: key, authenticating: Data(context.utf8)).combined!
    }

    static func open(_ data: Data, key: SymmetricKey, context: String) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: Data(context.utf8))
    }

    // MARK: PIN recovery

    struct PINDerived {
        let verifier: Data
        let wrapKey: SymmetricKey
    }

    static func stretch(pin: String, salt: Data, iterations: Int = pinIterations) -> PINDerived {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(pin.utf8)
        _ = salt.withUnsafeBytes { s in
            pw.withUnsafeBufferPointer { p in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) }, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
            }
        }
        let stretched = SymmetricKey(data: out)
        return PINDerived(verifier: derive(stretched, "tekkoh/pin-verifier/v1").data, wrapKey: derive(stretched, "tekkoh/pin-wrap/v1"))
    }

    /// The journal key locked with a PIN, for the server to keep.
    static func lock(journal: SymmetricKey, with p: PINDerived, handle: String) throws -> Data {
        try seal(journal.data, key: p.wrapKey, context: "tekkoh/recovery/\(handle)")
    }

    static func unlock(_ blob: Data, with p: PINDerived, handle: String) throws -> SymmetricKey {
        SymmetricKey(data: try open(blob, key: p.wrapKey, context: "tekkoh/recovery/\(handle)"))
    }

    static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return d
    }
}

extension SymmetricKey {
    var data: Data { withUnsafeBytes { Data($0) } }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
