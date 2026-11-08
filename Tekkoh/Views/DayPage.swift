import MapKit
import SwiftUI

/// The top of the page: a large serif date, the month and year as printed
/// labels, the weekday in Japanese, and the streak stamp.
struct DayHeader: View {
    let journal: Journal
    let day: String
    var large = false

    var body: some View {
        let date = Day.date(day)
        let written = journal.entries[day]?.hasContent ?? false
        HStack(alignment: .center, spacing: 14) {
            Text(date.formatted(.dateTime.day()))
                .font(.serif(large ? 76 : 60, .light))
                .monospacedDigit()
                .foregroundStyle(Weekday.color(day))
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 5) {
                Text(date.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.label(11)).tracking(2.5)
                    .foregroundStyle(Ink.text)
                HStack(spacing: 8) {
                    Text(Weekday.kanji[Weekday.of(day)])
                        .font(.serif(16, .medium))
                        .foregroundStyle(Weekday.color(day))
                    Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.label(10)).tracking(1.5)
                        .foregroundStyle(Ink.muted)
                }
                Text(dayOfYear(date))
                    .font(.label(9)).tracking(1)
                    .foregroundStyle(Ink.faint)
            }
            Spacer(minLength: 8)
            if day == Day.today || written {
                StreakStamp(days: stampCount, size: large ? 58 : 50, lit: written)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
        }
        .padding(.top, 4)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: written)
        .accessibilityElement(children: .combine)
    }

    /// Today shows the streak as it stands; a past day, the run it was part of.
    private var stampCount: Int {
        let days = journal.writtenDays
        if day == Day.today { return journal.streak }
        var n = 0, d = day
        while days.contains(d) { n += 1; d = Day.add(-1, to: d) }
        return n
    }

    private func dayOfYear(_ d: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let n = cal.ordinality(of: .day, in: .year, for: d) ?? 1
        let total = cal.range(of: .day, in: .year, for: d)?.count ?? 365
        return "\(n) / \(total)"
    }
}

/// The margin: where the day went, the sun, how far you moved.
struct MarginNotes: View {
    let entry: Entry
    let live: DayContext.Live
    let day: String
    var showMap = false

    var body: some View {
        let places = Place.combine(entry.places, live.places)
        let health = live.health ?? entry.health
        let sun = live.sun ?? entry.sun
        VStack(alignment: .leading, spacing: 7) {
            if showMap, !places.isEmpty {
                DayMap(places: places)
                    .frame(height: 170)
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Ink.grid, lineWidth: 0.5))
                    .padding(.bottom, 4)
            }
            ForEach(places.prefix(showMap ? 8 : 4)) { p in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().strokeBorder(Ink.vermillion, lineWidth: 1).frame(width: 6, height: 6)
                    Text("\(Text(p.name).foregroundStyle(Ink.text))\(Text(p.detail.isEmpty ? "" : "  \(p.detail)").foregroundStyle(Ink.muted))")
                        .font(.serif(13))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let a = p.arrived {
                        Text(a.formatted(date: .omitted, time: .shortened)).font(.label(9)).foregroundStyle(Ink.faint)
                    }
                }
            }
            if places.count > (showMap ? 8 : 4) {
                Text("+ \(places.count - (showMap ? 8 : 4)) more places").font(.label(9)).foregroundStyle(Ink.faint)
            }
            HStack(spacing: 14) {
                if let sun, let r = sun.rise, let s = sun.set {
                    Label {
                        Text("\(r.formatted(date: .omitted, time: .shortened)) – \(s.formatted(date: .omitted, time: .shortened))")
                    } icon: { Image(systemName: "sun.horizon") }
                }
                if let h = health {
                    if let st = h.steps, st > 0 {
                        Label("\(st.formatted()) steps", systemImage: "shoeprints.fill")
                    }
                    if let m = h.meters, m > 100 { Text(Distance.text(m)) }
                    if let f = h.flights, f > 0 { Text("\(f) fl") }
                }
            }
            .font(.label(10))
            .foregroundStyle(Ink.muted)
            .labelStyle(TightLabel())
            if let h = health, !h.workouts.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(h.workouts.prefix(3).enumerated()), id: \.offset) { _, w in
                        Text("\(w.kind) \(Int(w.minutes.rounded())) min" + (w.meters.map { $0 > 100 ? " · " + Distance.text($0) : "" } ?? ""))
                    }
                }
                .font(.label(10))
                .foregroundStyle(Ink.vermillion.opacity(0.85))
            }
        }
    }
}

/// Miles or kilometres, to a tenth, as the phone's region measures.
enum Distance {
    static func text(_ meters: Double) -> String {
        let unit: UnitLength = Locale.current.measurementSystem == .us ? .miles : .kilometers
        return Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title }
    }
}

/// The day's places on a quiet map, joined in the order they happened.
struct DayMap: View {
    let places: [Place]

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
            if places.count > 1 {
                MapPolyline(coordinates: places.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                    .stroke(Ink.vermillion.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }
            ForEach(places) { p in
                Annotation(p.name, coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon), anchor: .center) {
                    Circle().fill(Ink.paper).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Ink.vermillion, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .light)
        .mapControlVisibility(.hidden)
        .id(places.map(\.id).joined())
    }

    /// Every place in view with room around it, and never closer than a
    /// neighbourhood: one place alone shouldn't fill the map with rooftops.
    private var region: MKCoordinateRegion {
        let lats = places.map(\.lat), lons = places.map(\.lon)
        let center = CLLocationCoordinate2D(latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
                                            longitude: ((lons.min() ?? 0) + (lons.max() ?? 0)) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(((lats.max() ?? 0) - (lats.min() ?? 0)) * 1.6, 0.018),
                                    longitudeDelta: max(((lons.max() ?? 0) - (lons.min() ?? 0)) * 1.6, 0.018))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// Grid paper you write on. Saves as you go, a moment after you pause.
struct WritingSurface: View {
    let journal: Journal
    let day: String
    var roomy = false
    @Binding var writing: Bool
    @State private var text = ""
    @State private var loadedDay = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridPaper()
            if text.isEmpty {
                Text(day == Day.today ? "Today…" : "This day…")
                    .font(.serif(17).italic())
                    .foregroundStyle(Ink.faint)
                    .padding(.horizontal, roomy ? 33 : 25)
                    .padding(.top, roomy ? 32 : 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.serif(17))
                .lineSpacing(Ink.line - 20.3)
                .foregroundStyle(Ink.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, roomy ? 28 : 20)
                .padding(.vertical, roomy ? 24 : 12)
                .focused($focused)
                .accessibilityLabel("Today's writing")
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .task(id: day) {
            // Another device's words arriving land here too.
            loadedDay = day
            text = journal.entry(day).text
        }
        .onChange(of: journal.entries[day]?.text) { _, new in
            if !focused, let new, new != text { text = new }
        }
        .task(id: text) {
            guard loadedDay == day, text != journal.entry(day).text else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            journal.update(day) { $0.text = text }
        }
        .onChange(of: focused) { _, f in
            writing = f
            if !f, loadedDay == day, text != journal.entry(day).text { journal.update(day) { $0.text = text } }
        }
        // The tick in the bar puts the keyboard away.
        .onChange(of: writing) { _, w in if !w { focused = false } }
    }
}
