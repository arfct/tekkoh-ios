import Foundation
import UserNotifications

/// The evening nudge: at 9:30 pm, if today's page is blank, a reminder of
/// the streak that ends at midnight.
///
/// Notifications are scheduled ahead (the app may not run in the evening):
/// tonight's only if today is still blank; tomorrow's names the streak when
/// today is written, because then it's known; later ones are gentler, as
/// the streak by then depends on days not yet lived. Every save and every
/// launch reschedules them.
@MainActor
final class Reminders {
    static let shared = Reminders()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "tekkoh.nudge."

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "remind") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "remind") }
    }

    /// Minutes after midnight; 21:30 unless changed.
    var minute: Int {
        get { UserDefaults.standard.object(forKey: "remindAt") as? Int ?? 21 * 60 + 30 }
        set { UserDefaults.standard.set(newValue, forKey: "remindAt") }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func clear() {
        Task {
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func refresh(_ journal: Journal) {
        let streak = journal.streak
        let writtenToday = journal.writtenToday
        let enabled = enabled, minute = minute
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            center.removeAllDeliveredNotifications()
            guard enabled else { return }
            let today = Day.today
            for k in 0..<7 {
                if k == 0 && writtenToday { continue }
                let day = Day.add(k, to: today)
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Day.date(day))
                comps.hour = minute / 60
                comps.minute = minute % 60
                guard let when = Calendar.current.date(from: comps), when > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Today's page"
                content.body = Self.message(daysAhead: k, streak: streak, writtenToday: writtenToday)
                content.sound = .default
                content.threadIdentifier = "nudge"
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: prefix + day, content: content, trigger: trigger))
            }
        }
    }

    static func message(daysAhead k: Int, streak: Int, writtenToday: Bool) -> String {
        switch k {
        case 0 where streak > 0:
            return "Your \(streak)-day streak ends at midnight. A few lines will keep it going."
        case 0:
            return "Today's page is still blank. A few lines before bed?"
        case 1 where writtenToday && streak > 0:
            return "Your \(streak)-day streak ends at midnight. A few lines will keep it going."
        default:
            return "Today's page is still blank. A few lines before bed?"
        }
    }
}
