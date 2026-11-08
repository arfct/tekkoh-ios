import SwiftUI
import WidgetKit

@main
struct TekkohWidgets: WidgetBundle {
    var body: some Widget { TodayWidget() }
}

/// Today, quietly: the date as a notebook prints it, and the streak as a
/// brush circle. Home Screen, Lock Screen and StandBy.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: Provider()) { TodayView(entry: $0) }
            .configurationDisplayName("Today")
            .description("The day, and how many days in a row you've written.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let glance: Glance?

    var day: String { Day.key(date) }
    var streak: Int { glance?.streak(on: day) ?? 0 }
    var writtenToday: Bool { glance?.written(day) ?? false }
}

/// The widget changes only at midnight, or when the app saves a page and
/// asks for a reload.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, glance: Glance(run: 12, runEnd: Day.today, recent: (0..<7).map { Day.add(-$0, to: Day.today) }))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview && Glance.load() == nil ? placeholder(in: context) : DayEntry(date: .now, glance: Glance.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let glance = Glance.load()
        let midnight = Calendar.current.startOfDay(for: .now)
        let dates = [Date.now] + (1...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: midnight) }
        completion(Timeline(entries: dates.map { DayEntry(date: $0, glance: glance) }, policy: .atEnd))
    }
}

struct TodayView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.containerBackground(for: .widget) { Paper() }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium: Medium(entry: entry)
        case .accessoryCircular: Circular(entry: entry)
        case .accessoryRectangular: Rectangular(entry: entry)
        case .accessoryInline: Inline(entry: entry)
        default: Small(entry: entry)
        }
    }
}

// MARK: Pieces

/// Cream paper with the grid barely there.
private struct Paper: View {
    var body: some View {
        ZStack {
            Ink.paper
            GridPaper().opacity(0.45)
        }
    }
}

private extension DayEntry {
    var weekdayKanji: String { Weekday.kanji[Weekday.of(day)] }
    var weekdayColor: Color { Weekday.color(day) }
    var dayNumber: String { date.formatted(.dateTime.day()) }
    var weekdayName: String { date.formatted(.dateTime.weekday(.wide)).uppercased() }
    var monthName: String { date.formatted(.dateTime.month(.wide)).uppercased() }
    var monthYear: String { date.formatted(.dateTime.month(.wide).year()).uppercased() }

    /// Lit while the run is alive; the brush dries to grey when it ends.
    var lit: Bool { writtenToday || streak > 0 }

    var status: String {
        guard glance != nil else { return "Open Tekkoh to begin." }
        if writtenToday { return "Today's page is written." }
        return streak > 0 ? "A few lines keep it going." : "Begin a streak today."
    }
}

/// The last seven days as small beads, today on the right: filled where a
/// page was written, an open ring for today while it's still blank.
private struct Beads: View {
    let entry: DayEntry
    var size: CGFloat = 7

    var body: some View {
        HStack(spacing: size * 0.85) {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let d = Day.add(-back, to: entry.day)
                let on = entry.glance?.written(d) ?? false
                Circle()
                    .fill(on ? Ink.vermillion : Color.clear)
                    .overlay(Circle().strokeBorder(on ? Color.clear : back == 0 ? Ink.vermillion.opacity(0.7) : Ink.faint, lineWidth: 0.8))
                    .frame(width: size, height: size)
            }
        }
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// The streak inside an ensō, with the count set in the open circle.
private struct EnsoStreak: View {
    let entry: DayEntry
    var size: CGFloat

    var body: some View {
        ZStack {
            // Today's ink is still wet until the page is written: the
            // circle stays pale while the streak waits on today.
            Enso(size: size, color: entry.lit ? Ink.vermillion : Ink.faint)
                .opacity(entry.writtenToday || !entry.lit ? 1 : 0.4)
                .widgetAccentable()
            VStack(spacing: -size * 0.03) {
                Text("\(entry.streak)")
                    .font(.system(size: size * (entry.streak > 99 ? 0.24 : 0.3), weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text)
                    .contentTransition(.numericText())
                Text("連続")
                    .font(.system(size: size * 0.1, weight: .medium, design: .serif))
                    .foregroundStyle(Ink.muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(entry.streak)-day streak")
    }
}

// MARK: Families

/// The day's number large, the weekday as a printed kanji, and the streak
/// inside an ensō in the corner, pale until today's page is written.
private struct Small: View {
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.weekdayKanji)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(entry.weekdayColor)
                    .widgetAccentable()
                Text(entry.weekdayName.prefix(3))
                    .font(.label(9)).tracking(1.5)
                    .foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 0)
            Text(entry.dayNumber)
                .font(.system(size: 64, weight: .ultraLight, design: .serif))
                .foregroundStyle(Ink.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(entry.monthName)
                .font(.label(9)).tracking(2)
                .foregroundStyle(Ink.muted)
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                EnsoStreak(entry: entry, size: 58)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A spread: the date on the left page, the streak on the right, a fine
/// rule between them like a notebook's gutter.
private struct Medium: View {
    let entry: DayEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(entry.weekdayKanji)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(entry.weekdayColor)
                        .widgetAccentable()
                    Text(entry.weekdayName)
                        .font(.label(9)).tracking(1.5)
                        .foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 0)
                Text(entry.dayNumber)
                    .font(.system(size: 64, weight: .ultraLight, design: .serif))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text(entry.monthYear)
                    .font(.label(9)).tracking(2)
                    .foregroundStyle(Ink.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .fill(Ink.grid)
                .frame(width: 0.5)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)

            VStack(spacing: 8) {
                EnsoStreak(entry: entry, size: 86)
                Beads(entry: entry, size: 6)
                Text(entry.status)
                    .font(.serif(11)).italic()
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Lock Screen: the count inside a thin ring that fills with the week.
private struct Circular: View {
    let entry: DayEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: 0.92)
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-70))
                .opacity(entry.lit ? 1 : 0.35)
                .padding(3)
                .widgetAccentable()
            VStack(spacing: -2) {
                Text("\(entry.streak)")
                    .font(.system(size: entry.streak > 99 ? 17 : 21, weight: .regular, design: .serif))
                    .monospacedDigit()
                Text("連続").font(.system(size: 8, weight: .medium, design: .serif))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(entry.streak)-day streak")
    }
}

private struct Rectangular: View {
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(entry.weekdayKanji)  \(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .widgetAccentable()
            Text(entry.streak == 1 ? "1 day in a row" : "\(entry.streak) days in a row")
                .font(.serif(13))
            Text(entry.writtenToday ? "Today's page is written" : entry.streak > 0 ? "Today's page is blank" : "Begin today")
                .font(.serif(12)).italic()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Inline: View {
    let entry: DayEntry

    var body: some View {
        Text("\(entry.weekdayKanji) \(entry.dayNumber) · \(entry.streak)-day streak")
    }
}

#Preview(as: .systemSmall) { TodayWidget() } timeline: {
    DayEntry(date: .now, glance: Glance(run: 12, runEnd: Day.today, recent: (0..<6).map { Day.add(-$0, to: Day.today) }))
}

#Preview(as: .systemMedium) { TodayWidget() } timeline: {
    DayEntry(date: .now, glance: Glance(run: 12, runEnd: Day.add(-1, to: Day.today), recent: (1..<6).map { Day.add(-$0, to: Day.today) }))
}
