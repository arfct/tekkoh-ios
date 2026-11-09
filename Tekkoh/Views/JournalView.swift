import SwiftUI

/// The journal, open at a day. One page on a phone or the Duo's outside
/// display; on the inside display a two-page spread, like the notebook
/// open flat: the day's margin (date, places, movement, photos) on the left
/// page and the writing on the right, the fold running down the spine.
struct JournalView: View {
    let journal: Journal
    @State private var day = Day.today
    @State private var showIndex = false
    @State private var showSettings = false
    @State private var live = DayContext.Live()
    /// The keyboard's up: the bar shows a tick to put it away.
    @State private var writing = false
    /// On a wide spread, the margin page put away to write on its own.
    @AppStorage("focusWriting") private var focus = false
    /// Whether the layout is a side-by-side spread the margin can leave.
    @State private var canFocus = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Spread(fold: { g in Self.fold(g) }, focus: focus && canFocus, canFocus: $canFocus) {
                MarginPage(journal: journal, day: day, live: live, wide: true)
            } right: {
                WritingPage(journal: journal, day: day, live: live, writing: $writing, measure: focus && canFocus ? 620 : nil)
            } single: {
                SinglePage(journal: journal, day: day, live: live, writing: $writing)
            }
            .background(PageBackground())
            .gesture(swipe)
            // Haptics, kept to the moments that mean something.
            .sensoryFeedback(.selection, trigger: day)
            .sensoryFeedback(.impact(weight: .light), trigger: writing) { was, now in was && !now }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: focus)
            // Today's first words: the stamp lands.
            .sensoryFeedback(.success, trigger: journal.writtenToday) { was, now in !was && now }
            .toolbar { toolbar }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showIndex) {
                MonthIndex(journal: journal, selected: $day)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSettings) { SettingsView(journal: journal) }
            // An agent's link arrived: make way for it.
            .onChange(of: model.closeSheets) { showSettings = false; showIndex = false }
            .task(id: day) {
                live = DayContext.Live()
                live = await DayContext.gather(day)
                DayContext.fold(live, into: day, journal: journal)
            }
            .onChange(of: phase) { _, p in
                // A new day while away: open at today.
                if p == .active, day == Day.add(-1, to: Day.today), !journal.writtenToday { day = Day.today }
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { v in
                guard abs(v.translation.width) > 80, abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                go(v.translation.width < 0 ? 1 : -1)
            }
    }

    private func go(_ n: Int) {
        let next = Day.add(n, to: day)
        guard next <= Day.today else { return }
        withAnimation(.smooth(duration: 0.3)) { day = next }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { go(-1) } label: { Label("Previous day", systemImage: "chevron.left") }
            Button { go(1) } label: { Label("Next day", systemImage: "chevron.right") }
                .disabled(day >= Day.today)
            if day != Day.today {
                // Back to today, from an earlier page.
                Button { withAnimation(.smooth) { day = Day.today } } label: { Label("Go to today", systemImage: "forward.end") }
            }
        }
        if canFocus {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.smooth(duration: 0.35)) { focus.toggle() }
                } label: {
                    Label(focus ? "Show the margin" : "Focus on writing", systemImage: focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
            }
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                if focus && canFocus {
                    // With the margin away, the day still shows.
                    Text(Day.date(day).formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(.label(10)).tracking(1.5)
                        .foregroundStyle(Ink.text)
                    Text("·").foregroundStyle(Ink.faint)
                }
                SyncMark(journal: journal)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if writing {
                Button { writing = false } label: { Label("Done writing", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.vermillion)
            } else {
                Button { showIndex = true } label: { Label("Index", systemImage: "calendar") }
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
    }

    /// The fold while partly folded, in this view's coordinates.
    static func fold(_ g: GeometryProxy) -> CGRect? {
        guard let r = g.reservedRegions(kind: .division).first(where: \.isActive) else { return nil }
        var f = r.frame
        let bounds = CGRect(origin: .zero, size: g.size)
        if !bounds.intersects(f) {
            let o = g.frame(in: .global).origin
            f = f.offsetBy(dx: -o.x, dy: -o.y)
        }
        let c = f.intersection(bounds)
        return c.isNull || c.isEmpty ? nil : c
    }
}

/// Lays out two pages around a fold: side by side for a book (or any wide
/// screen), stacked for tabletop with the writing above the fold, and one
/// page otherwise.
struct Spread<Left: View, Right: View, Single: View>: View {
    let fold: (GeometryProxy) -> CGRect?
    /// Put the left page away and give the right the whole screen. Only on
    /// a flat spread: across a fold the writing would run over the hinge.
    var focus = false
    @Binding var canFocus: Bool
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right
    @ViewBuilder var single: Single

    var body: some View {
        GeometryReader { g in
            let size = g.size
            if let f = fold(g), f.width >= f.height, f.minY > 140, f.maxY < size.height - 140 {
                // Tabletop: write on the raised half, the margin lies flat.
                VStack(spacing: 0) {
                    right.frame(height: f.minY)
                    Color.clear.frame(height: f.height)
                    ScrollView { left }.frame(maxHeight: .infinity)
                }
            } else if let f = fold(g), f.height > f.width, f.minX > 260, f.maxX < size.width - 260 {
                HStack(spacing: 0) {
                    ScrollView { left }.frame(width: f.minX)
                    Spine().frame(width: max(f.width, 1))
                    right
                }
            } else if size.width >= 640 {
                HStack(spacing: 0) {
                    if !focus {
                        ScrollView { left }
                            .frame(width: (size.width / 2).rounded())
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Spine().frame(width: 1)
                            .transition(.opacity)
                    }
                    right
                }
            } else {
                single
            }
        }
        .onGeometryChange(for: Bool.self) { g in
            // The same test as above: a flat spread, not across a fold.
            g.size.width >= 640 && !Self.folded(g.size, fold(g))
        } action: { canFocus = $0 }
    }

    private static func folded(_ size: CGSize, _ fold: CGRect?) -> Bool {
        guard let f = fold, !f.isEmpty else { return false }
        return f.width >= f.height ? (f.minY > 140 && f.maxY < size.height - 140) : (f.minX > 260 && f.maxX < size.width - 260)
    }
}

/// Where the pages meet: a soft shadow either side of the gutter.
struct Spine: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.clear, .black.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
            Rectangle().fill(Ink.grid.opacity(0.8)).frame(width: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// The phone's page: everything in one scroll, writing first after the date.
struct SinglePage: View {
    let journal: Journal
    let day: String
    let live: DayContext.Live
    @Binding var writing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DayHeader(journal: journal, day: day)
                    .padding(.horizontal, 20)
                MarginNotes(entry: journal.entry(day), live: live, day: day)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                WritingSurface(journal: journal, day: day, writing: $writing)
                    .frame(minHeight: 340)
                    .padding(.top, 12)
                PhotoShelf(journal: journal, day: day, layout: .strip)
                    .padding(.top, 8)
                AgentNotesView(notes: journal.entry(day).notes)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// The left page of the spread.
struct MarginPage: View {
    let journal: Journal
    let day: String
    let live: DayContext.Live
    var wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DayHeader(journal: journal, day: day, large: true)
            MarginNotes(entry: journal.entry(day), live: live, day: day, showMap: true)
            AgentNotesView(notes: journal.entry(day).notes)
            PhotoShelf(journal: journal, day: day, layout: .grid)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }
}

/// The right page: just the grid and the words.
struct WritingPage: View {
    let journal: Journal
    let day: String
    let live: DayContext.Live
    @Binding var writing: Bool
    var measure: CGFloat? = nil

    var body: some View {
        WritingSurface(journal: journal, day: day, roomy: true, measure: measure, writing: $writing)
    }
}

/// Saved, saving, waiting for the network: a quiet mark in the title bar.
struct SyncMark: View {
    let journal: Journal

    var body: some View {
        Group {
            if journal.syncing {
                ProgressView().controlSize(.mini)
            } else if journal.pending > 0 {
                Label(journal.online ? "Saving" : "Offline · saved here", systemImage: journal.online ? "arrow.up.circle" : "icloud.slash")
            } else if journal.syncError != nil {
                Label("Not synced", systemImage: "exclamationmark.icloud")
            } else {
                Label("Saved", systemImage: "checkmark.icloud")
            }
        }
        .font(.label(10))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Ink.muted)
    }
}
