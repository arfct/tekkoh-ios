import CryptoKit
import Foundation

// Cross-checks with the web app (web/tests/vectors.mjs in arfct/tekkoh).
// `vectors make <file>`: writes values the Swift code produces from fixed
// keys, for the JavaScript to reproduce or open.
// `vectors check <file>`: opens what the JavaScript sealed.

let args = CommandLine.arguments
let K = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))
let browserPriv = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data((0..<32).map { UInt8(200 - $0) }))

if args[1] == "make" {
    var e = Entry(day: "2026-11-08", text: "Rain all morning. Tea, then the long way home.")
    e.photos = [Photo(id: "p_test", key: Data(repeating: 7, count: 32), caption: "the bridge", takenAt: Date(timeIntervalSinceReferenceDate: 784_000_000), width: 4, height: 3)]
    e.places = [Place(id: "1,2", name: "The bridge", detail: "Town", lat: 51.5, lon: -0.1, arrived: Date(timeIntervalSinceReferenceDate: 784_000_100))]
    e.version = 3
    let json = try! JSONEncoder.tekkoh.encode(e)
    let id = Crypto.entryID(K, day: e.day)
    let salt = Data(repeating: 9, count: 16)
    let d = Crypto.stretch(pin: "374912", salt: salt)
    let out: [String: String] = [
        "key": K.data.base64EncodedString(),
        "authToken": Crypto.authToken(K).base64EncodedString(),
        "day": e.day,
        "entryID": id,
        "entryJSON": String(decoding: json, as: UTF8.self),
        "sealedEntry": try! Crypto.sealEntry(json, id: id, journal: K).base64EncodedString(),
        "photo": try! Crypto.seal(Data("jpeg bytes".utf8), key: SymmetricKey(data: Data(repeating: 7, count: 32)), context: "tekkoh/photo/p_test").base64EncodedString(),
        "pin": "374912",
        "salt": salt.base64EncodedString(),
        "verifier": d.verifier.base64EncodedString(),
        "blob": try! Crypto.lock(journal: K, with: d, handle: "kiko").base64EncodedString(),
        "browserPrivate": browserPriv.rawRepresentation.base64URLString,
        "browserPublic": browserPriv.publicKey.rawRepresentation.base64URLString,
        "pairBox": try! Linking.seal(handle: "kiko", journal: K, to: browserPriv.publicKey).base64EncodedString(),
        "linkCode": Linking.code(browserPriv.publicKey.rawRepresentation),
    ]
    try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: args[2]))
    print("wrote vectors")
} else {
    let v = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: String]
    var failed = false
    let id = v["entryID"]!
    if let plain = try? Crypto.openEntry(Data(base64Encoded: v["sealedEntry"]!)!, id: id, journal: K),
       let e = try? JSONDecoder.tekkoh.decode(Entry.self, from: plain) {
        print("ok    Swift opens the web's page:", e.text, "photos:", e.photos.count, "version:", e.v)
        if e.text != v["text"] || e.photos.first?.caption != "from the web" || e.v != 4 { print("FAIL  web page fields"); failed = true }
    } else { print("FAIL  Swift can't open the web's page"); failed = true }
    exit(failed ? 1 : 0)
}

extension Data {
    var base64URLString: String { base64URL }
}
