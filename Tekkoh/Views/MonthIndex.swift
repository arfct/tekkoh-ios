import SwiftUI

/// The index, like a Techo's calendar pages: a month at a time, stepped
/// with ‹ › or a swipe, or zoomed out (pinch, or Year) to the whole year as
/// twelve small months. Days written are marked in vermillion; the streak
/// sits on top.
struct MonthIndex: View {
    let journal: Journal
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    enum Zoom: String, CaseIterable { case month = "Month", year = "Year" }
    @State private var zoom = Zoom.month
    @State private var month = String(Day.today.prefix(7)) // yyyy-MM
    @State private var direction = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    summary
                    pager
                    Group {
                        switch zoom {
                        case .month:
                            MonthGrid(month: month, written: journal.writtenDays, selected: selected, large: true) { d in
                                selected = d
                                dismiss()
                            }
                        case .year:
                            YearGrid(year: year, written: journal.writtenDays, selected: selected) { m in
                                month = m
                                withAnimation(.smooth(duration: 0.3)) { zoom = .month }
                            }
                        }
                    }
                    .id("\(zoom.rawValue)-\(zoom == .month ? month : year)")
                    .transition(.asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                                            removal: .opacity))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: zoom == .year ? 900 : 560)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .gesture(swipe)
            .sensoryFeedback(.selection, trigger: month)
            .sensoryFeedback(.impact(weight: .light), trigger: zoom)
            .simultaneousGesture(pinch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Zoom", selection: $zoom.animation(.smooth(duration: 0.3))) {
                        ForEach(Zoom.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { month = String(selected.prefix(7)) }
        }
    }

    private var year: String { String(month.prefix(4)) }
    private var thisMonth: String { String(Day.today.prefix(7)) }

    // MARK: Stepping

    private var pager: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel(zoom == .month ? "Previous month" : "Previous year")
            Spacer()
            VStack(spacing: 2) {
                if zoom == .month {
                    Text(Day.date(month + "-01").formatted(.dateTime.month(.wide)).uppercased())
                        .font(.label(13)).tracking(3).foregroundStyle(Ink.text)
                    Text(year).font(.label(10)).foregroundStyle(Ink.muted)
                } else {
                    Text(year).font(.serif(24)).monospacedDigit().foregroundStyle(Ink.text)
                    Text("\(journal.writtenDays.filter { $0.hasPrefix(year) }.count) pages").font(.label(9)).foregroundStyle(Ink.vermillion)
                }
            }
            .contentTransition(.numericText())
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(zoom == .month ? month >= thisMonth : year >= String(thisMonth.prefix(4)))
                .accessibilityLabel(zoom == .month ? "Next month" : "Next year")
        }
        .foregroundStyle(Ink.vermillion)
    }

    private func step(_ n: Int) {
        // Whole months: from the 1st, 31 days on is always next month.
        let target: String
        if zoom == .month {
            target = n > 0 ? String(Day.add(31, to: month + "-01").prefix(7)) : String(Day.add(-1, to: month + "-01").prefix(7))
        } else {
            let y = (Int(year) ?? 2026) + n
            target = String(format: "%04d-%@", y, String(month.suffix(2)))
        }
        guard target <= thisMonth || (zoom == .year && target.prefix(4) <= thisMonth.prefix(4)) else { return }
        direction = n
        withAnimation(.smooth(duration: 0.3)) { month = min(target, thisMonth) }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard abs(v.translation.width) > 70, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                step(v.translation.width < 0 ? 1 : -1)
            }
    }

    /// Pinch in to see the year, out to go back to the month.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onEnded { v in
                if v.magnification < 0.85, zoom == .month { withAnimation(.smooth(duration: 0.3)) { zoom = .year } }
                if v.magnification > 1.15, zoom == .year { withAnimation(.smooth(duration: 0.3)) { zoom = .month } }
            }
    }

    private var summary: some View {
        HStack(spacing: 22) {
            StreakStamp(days: journal.streak, size: 74, lit: journal.writtenToday || journal.streak > 0)
            VStack(alignment: .leading, spacing: 6) {
                Text(journal.writtenToday ? "Today's page is written." : journal.streak > 0 ? "Write today to keep it going." : "Begin a streak today.")
                    .font(.serif(17))
                    .foregroundStyle(Ink.text)
                HStack(spacing: 16) {
                    stat("\(journal.writtenDays.count)", "PAGES")
                    stat("\(journal.longestStreak)", "LONGEST")
                }
            }
        }
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(n).font(.serif(20)).monospacedDigit().foregroundStyle(Ink.text)
            Text(label).font(.label(8)).tracking(1.5).foregroundStyle(Ink.muted)
        }
    }
}

/// A year as twelve small months: written days as vermillion dots, a tap
/// opens the month.
struct YearGrid: View {
    let year: String
    let written: Set<String>
    let selected: String
    let open: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 22, alignment: .top)], alignment: .leading, spacing: 26) {
            ForEach(1...12, id: \.self) { m in
                let month = String(format: "%@-%02d", year, m)
                Button { open(month) } label: { MiniMonth(month: month, written: written, selected: selected) }
                    .buttonStyle(.plain)
                    .disabled(month > String(Day.today.prefix(7)))
            }
        }
    }
}

struct MiniMonth: View {
    let month: String
    let written: Set<String>
    let selected: String

    var body: some View {
        let first = Day.date(month + "-01")
        let cal = Calendar(identifier: .gregorian)
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = cal.component(.weekday, from: first) - 1
        let days = (1...count).map { String(format: "%@-%02d", month, $0) }
        let n = days.filter(written.contains).count
        let future = month > String(Day.today.prefix(7))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(first.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.label(10)).tracking(2)
                    .foregroundStyle(future ? Ink.faint : Ink.text)
                Spacer()
                if n > 0 { Text("\(n)").font(.label(9)).foregroundStyle(Ink.vermillion) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 14) }
                ForEach(days, id: \.self) { d in
                    ZStack {
                        if written.contains(d) {
                            Circle().fill(Ink.vermillion).frame(width: 13, height: 13)
                        } else if d == Day.today {
                            Circle().strokeBorder(Ink.vermillion, lineWidth: 1).frame(width: 13, height: 13)
                        }
                        Text("\(Int(d.suffix(2)) ?? 0)")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(written.contains(d) ? Ink.paper : d > Day.today ? Ink.faint.opacity(0.5) : Ink.muted)
                    }
                    .frame(height: 14)
                }
            }
        }
        .padding(10)
        .background(Ink.card.opacity(0.5), in: .rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(month == String(selected.prefix(7)) ? Ink.vermillion.opacity(0.5) : Ink.grid, lineWidth: 0.7))
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel("\(first.formatted(.dateTime.month(.wide).year())), \(n) pages")
    }
}

struct MonthGrid: View {
    let month: String // yyyy-MM
    let written: Set<String>
    let selected: String
    /// On its own, under the pager: bigger days, no heading of its own.
    var large = false
    let pick: (String) -> Void

    var body: some View {
        let first = Day.date(month + "-01")
        let cal = Calendar(identifier: .gregorian)
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = cal.component(.weekday, from: first) - 1
        let days = (1...count).map { String(format: "%@-%02d", month, $0) }
        let n = days.filter(written.contains).count
        let h: CGFloat = large ? 54 : 44
        VStack(alignment: .leading, spacing: 10) {
            if !large {
            HStack(alignment: .firstTextBaseline) {
                Text(first.formatted(.dateTime.month(.wide)).uppercased())
                    .font(.label(12)).tracking(3)
                    .foregroundStyle(Ink.text)
                Text(first.formatted(.dateTime.year()))
                    .font(.label(10)).foregroundStyle(Ink.muted)
                Spacer()
                if n > 0 { Text("\(n) pages").font(.label(9)).foregroundStyle(Ink.vermillion) }
            }
            }
            Rectangle().fill(Ink.text.opacity(0.7)).frame(height: 0.7)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Weekday.kanji[i])
                        .font(.serif(11))
                        .foregroundStyle(i == 0 ? Ink.vermillion : i == 6 ? Ink.indigo : Ink.muted)
                        .frame(height: 22)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: h) }
                ForEach(days, id: \.self) { d in cell(d, height: h) }
            }
            .background(GridPaper())
            if large {
                Text(n == 0 ? "No pages this month" : "\(n) \(n == 1 ? "page" : "pages") this month")
                    .font(.label(10)).foregroundStyle(n == 0 ? Ink.faint : Ink.vermillion)
            }
        }
    }

    private func cell(_ d: String, height: CGFloat) -> some View {
        let isWritten = written.contains(d)
        let future = d > Day.today
        let streakLeft = isWritten && written.contains(Day.add(-1, to: d)) && Weekday.of(d) != 0
        return Button { pick(d) } label: {
            ZStack {
                if streakLeft {
                    Rectangle().fill(Ink.vermillion.opacity(0.25)).frame(height: 1.5).offset(x: -22, y: 12)
                }
                VStack(spacing: 3) {
                    Text("\(Int(d.suffix(2)) ?? 0)")
                        .font(.serif(large ? 17 : 15, d == Day.today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(future ? Ink.faint : Weekday.color(d))
                    Circle()
                        .fill(isWritten ? Ink.vermillion : .clear)
                        .frame(width: 5, height: 5)
                }
                if d == selected {
                    Circle().strokeBorder(Ink.vermillion.opacity(0.7), lineWidth: 1).frame(width: 36, height: 36)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(Day.date(d).formatted(date: .complete, time: .omitted))\(isWritten ? ", written" : "")")
    }
}
