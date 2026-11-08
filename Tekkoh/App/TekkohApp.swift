import BackgroundTasks
import LocalAuthentication
import SwiftUI

@main
struct TekkohApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        // Created at launch so location visits reach the app even when the
        // system starts it in the background to deliver them.
        _ = Places.shared
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppModel.refreshTask, using: nil) { task in
            Task { @MainActor in
                await AppModel.backgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Ink.vermillion)
                .onChange(of: phase, initial: true) { _, p in
                    switch p {
                    case .active: model.becameActive()
                    case .background: model.wentToBackground()
                    default: break
                    }
                }
        }
    }
}

@MainActor @Observable
final class AppModel {
    static let refreshTask = "io.singleton.tekkoh.refresh"

    var journal: Journal?
    var locked = false
    var lockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "faceID") }
        set { UserDefaults.standard.set(newValue, forKey: "faceID") }
    }

    init() {
        if let id = Keychain.load() {
            journal = Journal(identity: id)
            locked = lockEnabled
        }
    }

    func signedIn(_ id: Keychain.Identity) {
        journal = Journal(identity: id)
        locked = false
        becameActive()
    }

    func signedOut() {
        journal?.signOut()
        Places.shared.forget()
        journal = nil
    }

    func becameActive() {
        guard let journal else { return }
        if locked { unlock() }
        journal.startMonitoring()
        Places.shared.start()
        Task {
            await journal.sync()
            await DayContext.refreshRecent(journal)
        }
    }

    func wentToBackground() {
        if lockEnabled { locked = true }
        let req = BGAppRefreshTaskRequest(identifier: Self.refreshTask)
        req.earliestBeginDate = .now.addingTimeInterval(3 * 3600)
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(req) }
    }

    func unlock() {
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your journal") { ok, _ in
            Task { @MainActor in if ok { self.locked = false } }
        }
    }

    /// In the background: sync, fold the day's places and activity into
    /// pages already written, and reschedule the evening nudge.
    static func backgroundRefresh() async {
        guard let id = Keychain.load() else { return }
        let j = Journal(identity: id)
        await j.sync()
        await DayContext.refreshRecent(j)
        Reminders.shared.refresh(j)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let journal = model.journal {
                if model.locked {
                    LockView()
                } else {
                    JournalView(journal: journal)
                }
            } else {
                Onboarding()
            }
        }
        .animation(.smooth(duration: 0.35), value: model.journal == nil)
        .animation(.smooth(duration: 0.25), value: model.locked)
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 28) {
                Enso(size: 140)
                Button("Open journal") { model.unlock() }
                    .font(.serif(17))
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// What surrounds a day's words: where it went, how it moved, the sun.
enum DayContext {
    struct Live: Equatable {
        var places: [Place] = []
        var health: Health?
        var sun: Sun?
    }

    static func gather(_ day: String) async -> Live {
        var l = Live()
        l.places = await Places.shared.places(for: day)
        l.health = await Activity.shared.snapshot(for: day)
        if let p = l.places.first {
            l.sun = SunTimes.compute(day: day, lat: p.lat, lon: p.lon)
        }
        return l
    }

    /// Writes a day's places and activity into its page, if it has one.
    @MainActor
    static func fold(_ live: Live, into day: String, journal: Journal) {
        guard let e = journal.entries[day], e.hasContent else { return }
        var n = e
        n.places = Place.combine(e.places, live.places)
        if let h = live.health { n.health = h }
        if let s = live.sun { n.sun = s }
        if n.places != e.places || n.health != e.health || n.sun != e.sun { journal.save(n) }
    }

    /// Today's and yesterday's pages pick up the rest of their day.
    @MainActor
    static func refreshRecent(_ journal: Journal) async {
        for day in [Day.today, Day.add(-1, to: Day.today)] where journal.entries[day]?.hasContent == true {
            fold(await gather(day), into: day, journal: journal)
        }
    }
}
