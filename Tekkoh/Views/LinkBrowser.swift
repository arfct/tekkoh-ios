import LocalAuthentication
import SwiftUI
import VisionKit

/// Linking a browser: scan the QR code tekkoh-web shows, check the six
/// digits match, and send it the journal key sealed to the one-time key in
/// the code. The browser also has your username and PIN, and links only if
/// they open the same key.
///
/// Or an agent's link, tapped: it arrives here already found, and the phone
/// is all that approves it, so it asks for Face ID (or the passcode) first.
struct LinkBrowser: View {
    let journal: Journal
    @Environment(\.dismiss) private var dismiss
    @State private var found: Linking.Code?
    private let fromLink: Bool
    /// Shown over the journal rather than as a sheet: how to put it away.
    private let onClose: (() -> Void)?

    init(journal: Journal, found: Linking.Code? = nil, onClose: (() -> Void)? = nil) {
        self.journal = journal
        _found = State(initialValue: found)
        fromLink = found != nil
        self.onClose = onClose
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }
    @State private var sending = false
    @State private var done = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground()
                if done {
                    VStack(spacing: 18) {
                        Enso(size: 90, draws: true)
                        Text("Linked").font(.serif(26)).foregroundStyle(Ink.text)
                        Text(found?.agent == true ? "The agent can open your journal now." : "The browser is opening your journal.").font(.serif(16)).foregroundStyle(Ink.muted)
                        Button("Done") { close() }.font(.serif(17)).padding(.top, 8)
                    }
                    .padding(30)
                } else if let code = found {
                    confirm(code)
                } else {
                    scanner
                }
            }
            .navigationTitle("Link a browser or agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } } }
            .sensoryFeedback(.success, trigger: done)
            .sensoryFeedback(.selection, trigger: found?.slot)
        }
    }

    @ViewBuilder private var scanner: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            VStack(spacing: 18) {
                QRScanner { text in
                    guard found == nil else { return }
                    if let c = Linking.parse(text) { found = c; error = nil } else { error = "That isn't a Tekkoh link code." }
                }
                .clipShape(.rect(cornerRadius: 12))
                .frame(maxHeight: 420)
                Text(error ?? "Open tekkoh-web.cronbon.com and enter your username and PIN, or open the link an agent sent you, and point the camera at the code it shows.")
                    .font(.serif(15))
                    .foregroundStyle(error == nil ? Ink.muted : Ink.vermillion)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        } else {
            Text("This phone can't scan codes right now. Check that Tekkoh is allowed to use the camera in Settings.")
                .font(.serif(16)).foregroundStyle(Ink.muted).multilineTextAlignment(.center).padding(30)
        }
    }

    private func confirm(_ code: Linking.Code) -> some View {
        let digits = Linking.code(code.raw)
        return VStack(alignment: .leading, spacing: 18) {
            Text(code.name.map { "Link \u{201C}\($0)\u{201D}?" } ?? (code.agent ? "Link this agent?" : "Link this browser?"))
                .font(.serif(26)).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(fromLink ? "An agent sent you this link. Its message should show the same six digits:"
                 : code.agent ? "Check the terminal shows the same six digits:" : "Check the browser shows the same six digits:")
                .font(.serif(16)).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(digits.prefix(3)) \(digits.suffix(3))")
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            Text(code.agent
                 ? "It will hold the key to \(journal.handle)'s journal: it can read every page and photo, write, and leave notes on what it did for you, until you sign it out here. Only link an agent you trust with everything you've written\(fromLink ? ", and only if you asked it to link just now" : "")."
                 : "It will be able to read and write \(journal.handle)'s journal until you sign it out here. It can't change your PIN or delete the journal.")
                .font(.serif(14)).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.label(11)).foregroundStyle(Ink.vermillion) }
            Spacer()
            Button {
                Task { await send(code) }
            } label: {
                Group { if sending { ProgressView() } else { Text("Link") } }
                    .font(.serif(18)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Ink.vermillion)
            .disabled(sending)
            if fromLink {
                Button("Don't link") { close() }
                    .font(.serif(15)).frame(maxWidth: .infinity)
            } else {
                Button("They're different") { found = nil; error = "Scan again, from the right page." }
                    .font(.serif(15)).frame(maxWidth: .infinity)
            }
        }
        .padding(28)
    }

    private func send(_ code: Linking.Code) async {
        sending = true
        defer { sending = false }
        // Handing over the key is the most this phone can give away: it
        // asks for its owner first, whatever the app lock is set to.
        guard await ownerPresent(code) else { return }
        do {
            let box = try Linking.seal(handle: journal.handle, journal: journal.key, to: code.browserKey)
            try await API(identity: journal.identity).link(slot: code.slot, box: box)
            done = true
        } catch let API.Failure.status(code, msg, _) {
            error = code == 404 ? (fromLink ? "That link has expired. Ask the agent for a new one." : "That code has expired. Show a new one in the browser.") : msg
        } catch {
            self.error = "Couldn't reach Tekkoh. Try again when you're online."
        }
    }
}

private func ownerPresent(_ code: Linking.Code) async -> Bool {
    let ctx = LAContext()
    var err: NSError?
    // A phone with no passcode at all can't be asked; it links as before.
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
    let what = code.name.map { "Link \u{201C}\($0)\u{201D} to your journal" } ?? (code.agent ? "Link an agent to your journal" : "Link a browser to your journal")
    return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: what)) ?? false
}

/// VisionKit's live QR scanner.
struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items { if let t = b.payloadStringValue { found(t) } }
        }
    }
}

/// The browsers linked to this journal, each signed out with a tap.
struct LinkedBrowsers: View {
    let journal: Journal
    @State private var browsers: [API.Browser] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if browsers.isEmpty {
                Text("Nothing linked.").foregroundStyle(Ink.muted)
            }
            ForEach(browsers) { b in
                HStack {
                    Image(systemName: b.agent ? "terminal" : "globe")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.muted)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.label)
                        if let u = b.lastUsed {
                            Text("Last used \(u.formatted(.relative(presentation: .named)))").font(.label(10)).foregroundStyle(Ink.muted)
                        }
                    }
                    Spacer()
                    Button("Sign out", role: .destructive) {
                        Task {
                            do {
                                try await API(identity: journal.identity).unlink(browser: b.id)
                                browsers.removeAll { $0.id == b.id }
                            } catch { self.error = "Couldn't reach Tekkoh." }
                        }
                    }
                    .font(.label(11))
                    .buttonStyle(.bordered)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Ink.vermillion) }
        }
        .task { await load() }
    }

    func load() async {
        browsers = (try? await API(identity: journal.identity).browsers()) ?? []
        loaded = true
    }
}
