import CoreLocation
import Photos
import SwiftUI

struct SettingsView: View {
    let journal: Journal
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var remind = Reminders.shared.enabled
    @State private var remindAt = Date.now
    @State private var faceID = UserDefaults.standard.bool(forKey: "faceID")
    @State private var changingPIN = false
    @State private var linking = false
    @State private var confirmSignOut = false
    @State private var deleting = false
    @State private var confirmHandle = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Username", value: journal.handle)
                    LabeledContent("Pages", value: "\(journal.writtenDays.count)")
                    LabeledContent("Sync") {
                        if journal.syncing { ProgressView() } else {
                            Text(status).foregroundStyle(journal.syncError == nil ? Ink.muted : Ink.vermillion)
                        }
                    }
                    Button("Sync now") { Task { await journal.sync() } }
                } header: {
                    Text("Journal")
                } footer: {
                    Text("Everything is encrypted on this phone before it leaves. The server keeps a copy it can't read, so your journal is backed up and on all your devices.")
                }

                Section("Evening reminder") {
                    Toggle("Remind me if today's page is blank", isOn: $remind)
                    DatePicker("At", selection: $remindAt, displayedComponents: .hourAndMinute)
                        .disabled(!remind)
                }

                Section {
                    permission("Places", Places.shared.authorization == .authorizedAlways ? "Always" : Places.shared.authorization == .authorizedWhenInUse ? "While using" : "Off") {
                        Places.shared.requestPermission()
                    }
                    permission("Activity", "Apple Health") { Task { await Activity.shared.requestPermission() } }
                    permission("Photos", photoStatus) { Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite) } }
                } header: {
                    Text("In the margins")
                } footer: {
                    Text("Change these any time in the Settings app; places and activity are written into each page, encrypted like everything else.")
                }

                Section {
                    LinkedBrowsers(journal: journal).id(linking)
                    Button("Link a browser") { linking = true }
                } header: {
                    Text("Browsers")
                } footer: {
                    Text("Read and write your journal at tekkoh-web.cronbon.com. A linked browser needs your username, your PIN and this phone, and can't change your PIN or delete the journal.")
                }

                Section("Privacy") {
                    Toggle("Lock with Face ID", isOn: $faceID)
                    Button("Change PIN") { changingPIN = true }
                }

                Section {
                    Button("Sign out of this phone", role: .destructive) { confirmSignOut = true }
                    Button("Delete journal everywhere", role: .destructive) { deleting = true }
                } footer: {
                    Text("Signing out removes the journal from this phone; its key stays in your iCloud Keychain for your other devices. Deleting removes it from the server and every device, for good.")
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Ink.vermillion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PageBackground())
            .font(.serif(16))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                let m = Reminders.shared.minute
                remindAt = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            }
            .onChange(of: remind) { _, v in
                Reminders.shared.enabled = v
                if v { Task { _ = await Reminders.shared.requestPermission() } }
                Reminders.shared.refresh(journal)
            }
            .onChange(of: remindAt) { _, d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                Reminders.shared.minute = (c.hour ?? 21) * 60 + (c.minute ?? 30)
                Reminders.shared.refresh(journal)
            }
            .onChange(of: faceID) { _, v in model.lockEnabled = v }
            .sheet(isPresented: $changingPIN) { ChangePIN(journal: journal) }
            .sheet(isPresented: $linking) { LinkBrowser(journal: journal) }
            .confirmationDialog("Sign out of this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    dismiss()
                    model.signedOut()
                }
            } message: {
                Text(journal.pending > 0 ? "\(journal.pending) changes haven't reached the server yet and will be lost." : "You'll need your username and PIN to open it again.")
            }
            .alert("Delete your journal?", isPresented: $deleting) {
                TextField(journal.handle, text: $confirmHandle).textInputAutocapitalization(.never)
                Button("Delete everything", role: .destructive) {
                    guard confirmHandle.lowercased() == journal.handle else { message = "That wasn't your username; nothing was deleted."; return }
                    Task {
                        do {
                            try await journal.deleteEverywhere()
                            Places.shared.forget()
                            AppModel.signedOutHere = false
                            dismiss()
                            model.journal = nil
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every page and photo, on the server and this phone. Type your username to confirm.")
            }
        }
    }

    private var status: String {
        if let e = journal.syncError { return e }
        if journal.pending > 0 { return journal.online ? "\(journal.pending) waiting" : "Offline · \(journal.pending) waiting" }
        if let t = journal.lastSynced { return "Up to date · \(t.formatted(date: .omitted, time: .shortened))" }
        return journal.online ? "Up to date" : "Offline"
    }

    private var photoStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "All photos"
        case .limited: return "Selected photos"
        case .notDetermined: return "Not asked"
        default: return "Off"
        }
    }

    private func permission(_ title: String, _ value: String, ask: @escaping () -> Void) -> some View {
        Button(action: ask) {
            LabeledContent(title, value: value).foregroundStyle(Ink.text)
        }
    }
}

struct ChangePIN: View {
    let journal: Journal
    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        ZStack {
            PageBackground()
            if saving {
                ProgressView("Saving…").font(.serif(16))
            } else if let f = first {
                PINPad(title: "Once more", error: error) { pin in
                    guard pin == f else { error = "Those didn't match."; first = nil; return }
                    saving = true
                    Task {
                        do {
                            try await journal.changePIN(pin)
                            AppModel.setPINBoxed(journal.handle)
                            AppModel.current?.needsNewPIN = nil
                            dismiss()
                        } catch {
                            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save it."
                            saving = false
                            first = nil
                        }
                    }
                }
            } else {
                PINPad(title: "A new PIN", subtitle: "Needs a connection: the server keeps your key locked with it.", error: error) { pin in
                    if let p = PINPolicy.problem(pin) { error = p; return }
                    error = nil
                    first = pin
                }
            }
        }
    }
}
