import Foundation

/// Sunrise and sunset for a day and place, worked out on the phone (NOAA's
/// approximation, good to a minute or two), as the old Tekkoh showed.
enum SunTimes {
    static func compute(day: String, lat: Double, lon: Double) -> Sun {
        let date = Day.date(day)
        let n = Double(Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: date) ?? 1)
        func event(rising: Bool) -> Date? {
            let lngHour = lon / 15
            let t = n + ((rising ? 6 : 18) - lngHour) / 24
            let m = 0.9856 * t - 3.289
            var l = m + 1.916 * sin(m.rad) + 0.020 * sin((2 * m).rad) + 282.634
            l = l.wrapped(360)
            var ra = atan(0.91764 * tan(l.rad)).deg.wrapped(360)
            ra += floor(l / 90) * 90 - floor(ra / 90) * 90
            ra /= 15
            let sinDec = 0.39782 * sin(l.rad)
            let cosDec = cos(asin(sinDec))
            let cosH = (cos(90.833.rad) - sinDec * sin(lat.rad)) / (cosDec * cos(lat.rad))
            guard cosH >= -1, cosH <= 1 else { return nil } // polar day or night
            let h = (rising ? 360 - acos(cosH).deg : acos(cosH).deg) / 15
            let localT = h + ra - 0.06571 * t - 6.622
            let ut = (localT - lngHour).wrapped(24)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            guard let midnight = utc.date(from: comps) else { return nil }
            var d = midnight.addingTimeInterval(ut * 3600)
            // Keep it on the local day.
            let span = Day.interval(day)
            if d < span.start { d += 86400 } else if d >= span.end { d -= 86400 }
            return d
        }
        return Sun(rise: event(rising: true), set: event(rising: false))
    }
}

private extension Double {
    var rad: Double { self * .pi / 180 }
    var deg: Double { self * 180 / .pi }
    func wrapped(_ m: Double) -> Double { let r = truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r }
}
