import SwiftUI

/// The index: month pages, like a Techo's monthly calendar. Days written are
/// marked in vermillion; the current streak and the longest sit on top.
struct MonthIndex: View {
    let journal: Journal
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        summary
                        ForEach(months, id: \.self) { m in
                            MonthGrid(month: m, written: journal.writtenDays, selected: selected) { d in
                                selected = d
                                dismiss()
                            }
                            .id(m)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { proxy.scrollTo(String(selected.prefix(7)), anchor: .center) }
            }
            .background(PageBackground())
            .navigationTitle("Index")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
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

    /// From the first written month (or this one) to now, oldest first.
    private var months: [String] {
        let first = journal.writtenDays.min() ?? Day.today
        var m = String(first.prefix(7)), out: [String] = []
        let now = String(Day.today.prefix(7))
        while m <= now {
            out.append(m)
            m = String(Day.add(32, to: m + "-01").prefix(7))
        }
        return out
    }
}

struct MonthGrid: View {
    let month: String // yyyy-MM
    let written: Set<String>
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        let first = Day.date(month + "-01")
        let cal = Calendar(identifier: .gregorian)
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = cal.component(.weekday, from: first) - 1
        let days = (1...count).map { String(format: "%@-%02d", month, $0) }
        let n = days.filter(written.contains).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(first.formatted(.dateTime.month(.wide)).uppercased())
                    .font(.label(12)).tracking(3)
                    .foregroundStyle(Ink.text)
                Text(first.formatted(.dateTime.year()))
                    .font(.label(10)).foregroundStyle(Ink.muted)
                Spacer()
                if n > 0 { Text("\(n) pages").font(.label(9)).foregroundStyle(Ink.vermillion) }
            }
            Rectangle().fill(Ink.text.opacity(0.7)).frame(height: 0.7)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Weekday.kanji[i])
                        .font(.serif(11))
                        .foregroundStyle(i == 0 ? Ink.vermillion : i == 6 ? Ink.indigo : Ink.muted)
                        .frame(height: 22)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(days, id: \.self) { d in cell(d) }
            }
            .background(GridPaper())
        }
    }

    private func cell(_ d: String) -> some View {
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
                        .font(.serif(15, d == Day.today ? .semibold : .regular))
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
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(Day.date(d).formatted(date: .complete, time: .omitted))\(isWritten ? ", written" : "")")
    }
}
