import Foundation
import WidgetKit

/// Keeps the widget's glance of the journal current.
enum WidgetGlance {
    @MainActor
    static func update(_ journal: Journal) {
        let days = journal.writtenDays, today = Day.today
        let end = days.contains(today) ? today : days.contains(Day.add(-1, to: today)) ? Day.add(-1, to: today) : nil
        let recent = (0..<14).map { Day.add(-$0, to: today) }.filter(days.contains)
        let glance = Glance(run: end == nil ? 0 : Streak.current(days, today: today), runEnd: end, recent: recent)
        if glance.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    static func clear() {
        Glance.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
