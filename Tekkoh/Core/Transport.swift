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
