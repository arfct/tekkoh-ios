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

    /// The app's one model, so background work uses the same journal
    /// rather than a second copy writing the same files.
    static weak var current: AppModel?

    var journal: Journal?
    var locked = false
    /// Set when the server no longer holds a usable PIN recovery: asks for
    /// a new PIN.
    var needsNewPIN: PINReason?
    /// An agent's link, tapped: waits for the journal to be open, then asks.
    var incomingLink: Linking.Code?

    enum PINReason: Identifiable {
        case wiped, exposed
        var id: Self { self }
    }

    /// Signing out of this phone leaves the key in iCloud Keychain (deleting
    /// it there deletes it everywhere), so this phone remembers not to open it.
    static var signedOutHere: Bool {
        get { UserDefaults.standard.bool(forKey: "signedOutHere") }
        set { UserDefaults.standard.set(newValue, forKey: "signedOutHere") }
    }

    /// Whether this phone set (or used) the PIN with recovery fields boxed
    /// to the server's key. Before that they travelled readable.
    static func pinBoxed(_ handle: String) -> Bool { UserDefaults.standard.bool(forKey: "pinBoxed.\(handle)") }
    static func setPINBoxed(_ handle: String) { UserDefaults.standard.set(true, forKey: "pinBoxed.\(handle)") }
    var lockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "faceID") }
        set { UserDefaults.standard.set(newValue, forKey: "faceID") }
    }

    init() {
        if !Self.signedOutHere, let id = Keychain.load() {
            journal = Journal(identity: id)
            locked = lockEnabled
        }
        Self.current = self
    }

    func signedIn(_ id: Keychain.Identity) {
        Self.signedOutHere = false
        journal = Journal(identity: id)
        locked = false
        becameActive()
    }

    func signedOut() {
        journal?.signOut()
        Places.shared.forget()
        Self.signedOutHere = true
        journal = nil
    }

    /// Asks for a new PIN if the server's recovery is gone (ten wrong tries
    /// by anyone wipe it) or was set when its fields travelled readable.
    func checkRecovery() async {
        guard let journal, needsNewPIN == nil else { return }
        guard let active = await journal.recoveryActive() else { return }
        if !active { needsNewPIN = .wiped } else if !Self.pinBoxed(journal.handle) { needsNewPIN = .exposed }
    }

    func becameActive() {
        guard let journal else { return }
        if locked { unlock() }
        journal.startMonitoring()
        Places.shared.start()
        Task {
            await journal.sync()
            await DayContext.refreshRecent(journal)
            await checkRecovery()
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
        let j: Journal
        if let open = current?.journal {
            j = open
        } else {
            guard !signedOutHere, let id = Keychain.load() else { return }
            j = Journal(identity: id)
        }
        await j.sync()
        await DayContext.refreshRecent(j)
        Reminders.shared.refresh(j)
        WidgetGlance.update(j)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    /// Opening the journal: blank paper, the brush draws the ensō, and the
    /// page shows through. At launch and on every return from the background.
    @State private var opening = true
    @State private var openings = 0
    @State private var wasAway = false

    var body: some View {
        @Bindable var model = model
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
        // An agent's link: shown once the journal is open, past the lock.
        .sheet(item: Binding(get: { model.locked || model.journal == nil ? nil : model.incomingLink },
                             set: { model.incomingLink = $0 })) { code in
            if let j = model.journal { LinkBrowser(journal: j, found: code) }
        }
        .animation(.smooth(duration: 0.35), value: model.journal == nil)
        .animation(.smooth(duration: 0.25), value: model.locked)
        .overlay {
            if opening && model.journal != nil && !model.locked {
                ZStack {
                    PageBackground()
                    Enso(size: 140, draws: true).id(openings)
                }
                .contentShape(.rect)
                .onTapGesture { withAnimation(.easeOut(duration: 0.3)) { opening = false } }
                .transition(.opacity)
                .task(id: openings) {
                    try? await Task.sleep(for: .milliseconds(1900))
                    withAnimation(.easeInOut(duration: 0.5)) { opening = false }
                }
            }
        }
        // The app switcher's snapshot shows blank paper, not a page, and
        // the brush starts from it when you come back.
        .overlay {
            if phase != .active && model.journal != nil {
                PageBackground().transition(.opacity)
            }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .background:
                wasAway = true
            case .active where wasAway:
                wasAway = false
                // With the Face ID lock on, the lock screen draws it instead.
                if !model.locked {
                    openings += 1
                    opening = true
                }
            default:
                break
            }
        }
        .onOpenURL { url in
            if let code = Linking.parse(url: url) { model.incomingLink = code }
        }
        .onChange(of: model.locked, initial: true) { _, locked in
            if locked { opening = false }
        }
        .sheet(item: $model.needsNewPIN) { reason in
            if let j = model.journal { NewPINPrompt(journal: j, reason: reason) }
        }
    }
}

/// When the server's PIN recovery is gone or may have been seen: choose a
/// new PIN. The journal itself is unaffected; this is about a future phone.
struct NewPINPrompt: View {
    let journal: Journal
    let reason: AppModel.PINReason
    @State private var choosing = false

    var body: some View {
        ZStack {
            PageBackground()
            if choosing {
                ChangePIN(journal: journal)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Enso(size: 70, draws: true)
                    Text("Choose a new PIN").font(.serif(26)).foregroundStyle(Ink.text)
                    Text(reason == .wiped
                         ? "Someone made ten wrong guesses at your PIN, so the server has destroyed your recovery copy, as it's meant to. Your journal is safe and open on this phone, but a new phone couldn't get it back until you choose a new PIN."
                         : "An earlier version of Tekkoh sent your PIN's recovery information in a form the server's operator, or a network in between, could have used to guess your PIN. Choose a new one: it travels sealed now.")
                        .font(.serif(16)).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { choosing = true } label: {
                        Text("Choose a new PIN").font(.serif(18)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.vermillion)
                }
                .padding(30)
            }
        }
        .interactiveDismissDisabled(reason == .wiped)
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 28) {
                Enso(size: 140, draws: true)
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
