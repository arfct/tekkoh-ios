import CryptoKit
import HealthKit
import Photos
import SwiftUI

/// First run: start a journal (username, PIN, permissions) or bring one back
/// on a new phone (username, PIN).
struct Onboarding: View {
    @Environment(AppModel.self) private var model
    enum Step: Hashable { case welcome, username(restore: Bool), pin(handle: String), confirm(handle: String, pin: String), restorePIN(handle: String), working(String), permissions }
    @State private var step: Step = .welcome
    @State private var handle = ""
    @State private var error: String?
    @State private var identity: Keychain.Identity?

    var body: some View {
        ZStack {
            PageBackground()
            GridPaper().opacity(0.5).ignoresSafeArea()
            content
                .padding(.horizontal, 30)
                .frame(maxWidth: 460)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                .id(step)
        }
        .animation(.smooth(duration: 0.35), value: step)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .username(let restore): username(restore)
        case .pin(let h):
            PINPad(title: "Choose a 6-digit PIN",
                   subtitle: "It brings your journal back on a new phone. Only you know it: Tekkoh can't reset it, and ten wrong tries lock it for good.") { pin in
                error = nil
                step = .confirm(handle: h, pin: pin)
            }
        case .confirm(let h, let first):
            PINPad(title: "Once more", subtitle: "The same six digits.", error: error) { pin in
                guard pin == first else {
                    error = "Those didn't match. Start again."
                    Task { try? await Task.sleep(for: .seconds(1)); step = .pin(handle: h); error = nil }
                    return
                }
                Task { await create(handle: h, pin: pin) }
            }
        case .restorePIN(let h):
            PINPad(title: "Your PIN", subtitle: "For \(h).", error: error) { pin in
                Task { await restore(handle: h, pin: pin) }
            }
        case .working(let what):
            VStack(spacing: 24) {
                Enso(size: 110)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                Text(what).font(.serif(17)).foregroundStyle(Ink.muted)
            }
        case .permissions: PermissionsStep { if let identity { model.signedIn(identity) } }
        }
    }

    @State private var spin = false

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Enso(size: 150)
            Text("Tekkoh")
                .font(.serif(44, .light))
                .tracking(2)
                .foregroundStyle(Ink.text)
                .padding(.top, 18)
            Text("日記")
                .font(.serif(15))
                .foregroundStyle(Ink.vermillion)
                .padding(.top, 2)
            Text("A page a day, for your eyes only.\nEncrypted on this phone with a key only you hold.")
                .font(.serif(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Ink.muted)
                .padding(.top, 22)
            Spacer()
            Button { step = .username(restore: false) } label: {
                Text("Start a journal").font(.serif(18)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Ink.vermillion)
            Button("I already have one") { step = .username(restore: true) }
                .font(.serif(16))
                .padding(.top, 14)
                .padding(.bottom, 30)
        }
    }

    private func username(_ restore: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(restore ? "Your username" : "Choose a username")
                .font(.serif(26)).foregroundStyle(Ink.text)
            Text(restore ? "The one you chose when you started your journal." : "It's how you'll find your journal on a new phone. No email, no name: just this and your PIN.")
                .font(.serif(15)).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("username", text: $handle)
                .font(.serif(22))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Ink.text.opacity(0.6)).frame(height: 0.7) }
                .onSubmit { next(restore) }
            Text(error ?? " ").font(.label(11)).foregroundStyle(Ink.vermillion)
            Spacer()
            HStack {
                Button("Back") { error = nil; step = .welcome }.font(.serif(16))
                Spacer()
                Button { next(restore) } label: { Text("Next").font(.serif(18)).padding(.horizontal, 10) }
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.vermillion)
                    .disabled(clean.count < 3)
            }
            .padding(.bottom, 30)
        }
    }

    private var clean: String { handle.trimmingCharacters(in: .whitespaces).lowercased() }

    private func next(_ restore: Bool) {
        let h = clean
        guard h.range(of: #"^[a-z0-9][a-z0-9_.-]{2,29}$"#, options: .regularExpression) != nil else {
            error = "3 to 30 letters, digits, dots, dashes or underscores."
            return
        }
        error = nil
        step = restore ? .restorePIN(handle: h) : .pin(handle: h)
    }

    private func create(handle h: String, pin: String) async {
        step = .working("Making your key…")
        let key = SymmetricKey(size: .bits256)
        do {
            try await API().createAccount(handle: h, journal: key, pin: pin)
            let id = Keychain.Identity(handle: h, key: key.data)
            try Keychain.save(id)
            identity = id
            step = .permissions
        } catch let API.Failure.status(code, msg, _) {
            error = code == 409 ? "Someone already has that username." : msg
            step = .username(restore: false)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Tekkoh. Try again when you're online."
            step = .username(restore: false)
        }
    }

    private func restore(handle h: String, pin: String) async {
        step = .working("Unlocking…")
        do {
            let api = API()
            let params = try await api.recoveryParams(handle: h)
            let derived = await Task.detached { Crypto.stretch(pin: pin, salt: params.salt, iterations: params.iterations) }.value
            let blob = try await api.recover(handle: h, verifier: derived.verifier)
            let key = try Crypto.unlock(blob, with: derived, handle: h)
            let id = Keychain.Identity(handle: h, key: key.data)
            try Keychain.save(id)
            identity = id
            step = .working("Fetching your pages…")
            let j = Journal(identity: id)
            await j.sync()
            step = .permissions
        } catch let API.Failure.status(code, msg, obj) {
            switch code {
            case 403:
                let left = obj["attemptsLeft"] as? Int ?? 0
                error = "Wrong PIN. \(left) \(left == 1 ? "try" : "tries") left."
                step = .restorePIN(handle: h)
            case 404:
                error = "No journal with that username."
                step = .username(restore: true)
            case 410:
                error = "Too many wrong PINs: this journal now opens only on a device that still has its key."
                step = .username(restore: true)
            default:
                error = msg
                step = .restorePIN(handle: h)
            }
        } catch {
            self.error = "Couldn't reach Tekkoh. Try again when you're online."
            step = .restorePIN(handle: h)
        }
    }
}

/// What makes a page more than words, each asked for with its reason.
struct PermissionsStep: View {
    let finish: () -> Void
    @State private var asked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("Fill in the margins").font(.serif(26)).foregroundStyle(Ink.text)
            Text("Each is optional, stays encrypted in your journal, and can be changed in Settings.")
                .font(.serif(15)).foregroundStyle(Ink.muted)
            row("bell", "Evening reminder", "At 9:30 pm, if today's page is blank, a nudge about your streak.", "reminders") {
                _ = await Reminders.shared.requestPermission()
            }
            row("mappin.and.ellipse", "Places", "Where your day took you, noted on its page. Choose “Always” so it can follow the whole day.", "places") {
                Places.shared.requestPermission()
            }
            row("figure.walk", "Activity", "Steps, distance and workouts from Apple Health.", "health") {
                await Activity.shared.requestPermission()
            }
            row("photo.on.rectangle", "Photos", "Suggests the day's photos so you can add them in a tap.", "photos") {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            Spacer()
            Button { finish() } label: {
                Text("Open my journal").font(.serif(18)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Ink.vermillion)
            .padding(.bottom, 30)
        }
    }

    private func row(_ icon: String, _ title: String, _ text: String, _ id: String, ask: @escaping () async -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(Ink.vermillion).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.serif(17)).foregroundStyle(Ink.text)
                Text(text).font(.serif(13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(asked.contains(id) ? "Done" : "Allow") {
                Task { await ask(); asked.insert(id) }
            }
            .font(.label(11))
            .buttonStyle(.bordered)
            .disabled(asked.contains(id))
        }
    }
}
