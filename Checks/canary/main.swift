import CryptoKit
import Foundation

// The canary: a throwaway journal whose page, caption, place and photo all
// carry a unique marker, written through the app's own crypto and API.
// `canary write <file>` creates it and saves its identity to <file>;
// `canary delete <file>` removes the account. Between the two, canary.sh
// searches everything the server side holds for the marker.

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: canary write|delete <identity file>"); exit(2) }
let file = URL(fileURLWithPath: args[2])
let sem = DispatchSemaphore(value: 0)
var code: Int32 = 0

Task {
    do {
        if args[1] == "write" {
            let marker = "canary" + Crypto.randomBytes(6).map { String(format: "%02x", $0) }.joined()
            let handle = "canary" + Crypto.randomBytes(4).map { String(format: "%02x", $0) }.joined()
            let key = SymmetricKey(size: .bits256)
            let pin = "\(Int.random(in: 100_000...999_999))"
            try await API().createAccount(handle: handle, journal: key, pin: pin)
            let id = Keychain.Identity(handle: handle, key: key.data)
            let api = API(identity: id)

            // A photo whose plaintext is full of the marker.
            let photoID = Crypto.randomID("p_")
            let photoKey = SymmetricKey(size: .bits256)
            let photoPlain = Data((String(repeating: marker + " ", count: 200)).utf8)
            try await api.put(blob: photoID, data: try Crypto.seal(photoPlain, key: photoKey, context: "tekkoh/photo/\(photoID)"))

            var e = Entry(day: Day.today, text: "The \(marker) page. " + String(repeating: "\(marker) ", count: 20))
            e.photos = [Photo(id: photoID, key: photoKey.data, caption: "caption \(marker)", width: 1, height: 1)]
            e.places = [Place(id: "1,1", name: "Place \(marker)", detail: "City \(marker)", lat: 37.77, lon: -122.42)]
            let eid = Crypto.entryID(key, day: e.day)
            _ = try await api.put(entry: eid, data: try Crypto.sealEntry(try JSONEncoder.tekkoh.encode(e), id: eid, journal: key), rev: 0)

            let saved: [String: String] = ["handle": handle, "key": key.data.base64EncodedString(), "marker": marker, "pin": pin, "photo": photoID, "entry": eid]
            try JSONSerialization.data(withJSONObject: saved).write(to: file)
            print(handle, marker, pin)
        } else {
            let o = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: String]
            try await API(identity: Keychain.Identity(handle: o["handle"]!, key: Data(base64Encoded: o["key"]!)!)).deleteAccount()
            print("deleted", o["handle"]!)
        }
    } catch {
        print("canary:", error)
        code = 1
    }
    sem.signal()
}
sem.wait()
exit(code)
