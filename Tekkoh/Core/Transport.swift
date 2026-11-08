import CryptoKit
import Foundation

/// Recovery fields travel encrypted to the server's own X25519 key, which
/// is built into the app, so nothing between the phone and the server
/// process (Cloudflare's edge, a proxy) can see them. The PIN's verifier or
/// the PIN-locked key would each be enough to try every PIN offline.
///
/// k = HKDF-SHA256(X25519(eph, server), salt: eph ‖ server, info: "tekkoh/transport/v1/" + purpose);
/// the request is AES-256-GCM(k, JSON, aad: purpose), a reply the same with
/// aad purpose + "/reply". The server's half is in tekkoh-berth's transport.go.
enum Transport {
    /// GET /v1/transport-key on tekkoh.cronbon.com, built in so a server
    /// (or anything pretending to be one) can't swap it.
    static let serverKey = try! Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: "SiOqxMKXLVclQsetdJkLdHhmk1TgexDAZZSlF/i6O2E=")!)

    struct Box {
        let body: [String: String]
        let key: SymmetricKey
        let purpose: String

        func open(_ reply: Data) throws -> [String: Any] {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: reply), using: key, authenticating: Data((purpose + "/reply").utf8))
            return (try JSONSerialization.jsonObject(with: plain)) as? [String: Any] ?? [:]
        }
    }

    static func seal(_ fields: [String: Any], purpose: String, to server: Curve25519.KeyAgreement.PublicKey = serverKey) throws -> Box {
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: server)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: eph.publicKey.rawRepresentation + server.rawRepresentation,
                                                 sharedInfo: Data("tekkoh/transport/v1/\(purpose)".utf8), outputByteCount: 32)
        let plain = try JSONSerialization.data(withJSONObject: fields)
        let box = try AES.GCM.seal(plain, using: key, authenticating: Data(purpose.utf8)).combined!
        return Box(body: ["eph": eph.publicKey.rawRepresentation.base64EncodedString(), "box": box.base64EncodedString()], key: key, purpose: purpose)
    }
}

/// Linking a browser: the phone seals the journal key to the one-time
/// X25519 key the browser shows in its QR code. The box is the phone's
/// one-time public key followed by AES-GCM, with the same key derivation as
/// a transport box (purpose "pair"); web/js/crypto.js opens it.
enum Linking {
    struct Code {
        let slot: String
        let browserKey: Curve25519.KeyAgreement.PublicKey
        let raw: Data
    }

    /// The QR code's text: `tekkoh-link:1:<slot>:<base64url public key>`.
    static func parse(_ text: String) -> Code? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 4, parts[0] == "tekkoh-link", parts[1] == "1",
              parts[2].range(of: "^[A-Za-z0-9_-]{16,64}$", options: .regularExpression) != nil,
              let raw = Data(base64URL: parts[3]), raw.count == 32,
              let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else { return nil }
        return Code(slot: parts[2], browserKey: key, raw: raw)
    }

    static func seal(handle: String, journal: SymmetricKey, to browser: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["handle": handle, "key": journal.data.base64EncodedString()])
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: browser)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: eph.publicKey.rawRepresentation + browser.rawRepresentation,
                                                 sharedInfo: Data("tekkoh/transport/v1/pair".utf8), outputByteCount: 32)
        return eph.publicKey.rawRepresentation + (try AES.GCM.seal(payload, using: key, authenticating: Data("pair".utf8)).combined!)
    }

    /// Six digits the browser shows too, so you can see the phone found the
    /// right page.
    static func code(_ browserKey: Data) -> String {
        let h = Array(SHA256.hash(data: browserKey))
        return String(format: "%06d", ((Int(h[0]) << 16) | (Int(h[1]) << 8) | Int(h[2])) % 1_000_000)
    }
}

extension Data {
    init?(base64URL s: String) {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        self.init(base64Encoded: t)
    }
}
