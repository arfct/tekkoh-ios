import CoreLocation
import CryptoKit
import Foundation
import MapKit

/// Where the day went: visits and significant moves from Core Location,
/// kept on the phone (sealed with a key from the journal key) and named
/// with MapKit, then written into the day's page.
///
/// Visit monitoring and significant-change updates wake the app even after
/// it's been closed, with little battery cost, so the manager is created as
/// the app launches.
@MainActor
final class Places: NSObject, CLLocationManagerDelegate {
    static let shared = Places()

    struct Sample: Codable {
        var lat: Double
        var lon: Double
        var at: Date
        var arrived: Date?
        var departed: Date?
        var name: String?
        var detail: String?
    }

    private let manager = CLLocationManager()
    private var samples: [Sample] = []
    private var loaded = false
    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: Permission and tracking

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func start() {
        let s = manager.authorizationStatus
        guard s == .authorizedAlways || s == .authorizedWhenInUse else { return }
        manager.startMonitoringVisits()
        if s == .authorizedAlways { manager.startMonitoringSignificantLocationChanges() }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            // Ask for "Always" once "While Using" is granted: visits need it.
            if m.authorizationStatus == .authorizedWhenInUse && !UserDefaults.standard.bool(forKey: "askedAlways") {
                UserDefaults.standard.set(true, forKey: "askedAlways")
                m.requestAlwaysAuthorization()
            }
            self.start()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didVisit v: CLVisit) {
        let arrived = v.arrivalDate == .distantPast ? nil : v.arrivalDate
        let departed = v.departureDate == .distantFuture ? nil : v.departureDate
        let s = Sample(lat: v.coordinate.latitude, lon: v.coordinate.longitude, at: arrived ?? departed ?? .now, arrived: arrived, departed: departed)
        Task { @MainActor in self.add(s) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        let fresh = locs.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 1500 }
            .map { Sample(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, at: $0.timestamp) }
        Task { @MainActor in fresh.forEach(self.add) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    private func add(_ s: Sample) {
        load()
        // A point within 150 m of the last one in the last half hour adds nothing.
        if let last = samples.last, s.arrived == nil, s.departed == nil,
           s.at.timeIntervalSince(last.at) < 1800, distance(last, s) < 150 { return }
        samples.append(s)
        let cutoff = Date.now.addingTimeInterval(-60 * 86400)
        samples.removeAll { $0.at < cutoff }
        save()
    }

    // MARK: A day's places

    /// The day's places, nearby points grouped, each named once.
    func places(for day: String) async -> [Place] {
        load()
        let span = Day.interval(day)
        let inDay = samples.indices.filter { i in
            let s = samples[i]
            let from = s.arrived ?? s.at, to = s.departed ?? s.at
            return to >= span.start && from < span.end
        }
        var clusters: [[Int]] = []
        for i in inDay {
            if let c = clusters.firstIndex(where: { distance(samples[$0[0]], samples[i]) < 250 }) {
                clusters[c].append(i)
            } else {
                clusters.append([i])
            }
        }
        var out: [Place] = []
        for c in clusters {
            let first = c[0]
            if samples[first].name == nil {
                let named = await name(samples[first])
                for i in c { samples[i].name = named.0; samples[i].detail = named.1 }
            }
            let s = samples[first]
            guard let n = s.name, !n.isEmpty else { continue }
            let arrived = c.compactMap { samples[$0].arrived ?? samples[$0].at }.min()
            let departed = c.compactMap { samples[$0].departed ?? samples[$0].at }.max()
            out.append(Place(id: "\(Int(s.lat * 1000)),\(Int(s.lon * 1000))", name: n, detail: s.detail ?? "",
                             lat: s.lat, lon: s.lon, arrived: arrived, departed: departed))
        }
        save()
        return Place.combine(out, [])
    }

    private func name(_ s: Sample) async -> (String, String) {
        guard let req = MKReverseGeocodingRequest(location: CLLocation(latitude: s.lat, longitude: s.lon)),
              let item = try? await req.mapItems.first else { return ("", "") }
        let city = item.addressRepresentations?.cityWithContext ?? item.addressRepresentations?.cityName ?? ""
        let name = item.name ?? item.address?.shortAddress ?? city
        return (name, name == city ? (item.addressRepresentations?.regionName ?? "") : city)
    }

    private func distance(_ a: Sample, _ b: Sample) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
    }

    // MARK: Storage

    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Tekkoh/places.tek")
    }

    private var key: SymmetricKey? {
        Keychain.load().map { Crypto.derive($0.journalKey, "tekkoh/local/places/v1") }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let key, let d = try? Data(contentsOf: file),
              let plain = try? Crypto.open(d, key: key, context: "tekkoh/places"),
              let s = try? JSONDecoder().decode([Sample].self, from: plain) else { return }
        samples = s + samples
    }

    private func save() {
        // Without a journal yet there's no key: keep them in memory.
        guard let key, let plain = try? JSONEncoder().encode(samples),
              let sealed = try? Crypto.seal(plain, key: key, context: "tekkoh/places") else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? sealed.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func forget() {
        samples = []
        try? FileManager.default.removeItem(at: file)
    }
}
