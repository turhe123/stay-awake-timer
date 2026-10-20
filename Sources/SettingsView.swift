import SwiftUI
import AppKit
import ServiceManagement

/// Preferences: trigger apps, battery guard, display sleep, notifications and launch at login.
struct SettingsView: View {
    @EnvironmentObject private var controller: AwakeController
    @AppStorage(Prefs.batteryGuard) private var batteryGuard = 0
    @AppStorage(Prefs.allowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(Prefs.notifyOnEnd) private var notifyOnEnd = true
    @State private var apps: [TriggerApp] = TriggerApp.load()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Trigger Apps") {
                if apps.isEmpty {
                    Text("No apps chosen").foregroundStyle(.secondary)
                } else {
                    ForEach(apps) { app in
                        HStack {
                            Image(nsImage: icon(for: app.bundleID))
                                .resizable().frame(width: 18, height: 18)
                            Text(app.name)
                            Spacer()
                            Button(role: .destructive) { remove(app) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove \(app.name)")
                        }
                    }
                }
                Menu("Add Running App…") {
                    ForEach(candidates, id: \.bundleID) { app in
                        Button(app.name) { add(app) }
                    }
                }
                .disabled(candidates.isEmpty)
            }

            Section {
                Slider(value: Binding(get: { Double(batteryGuard) }, set: { batteryGuard = Int($0) }),
                       in: 0...50, step: 5) {
                    Text(batteryGuard == 0 ? "Battery guard: Off" : "Stop below \(batteryGuard)%")
                }
                if let pct = controller.batteryPercent {
                    Text("Current charge: \(pct)%").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Battery Guard") }

            Section {
                Toggle("Allow display to sleep while system stays awake", isOn: $allowDisplaySleep)
                Toggle("Notify when a session ends", isOn: $notifyOnEnd)
                    .onChange(of: notifyOnEnd) { _, on in if on { AwakeController.requestNotificationPermission() } }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } header: { Text("General") } footer: {
                Text("Closing the lid of a laptop without an external display still puts your Mac to sleep — macOS enforces this regardless of power assertions. Timers are not restored after relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("StayAwakeTimer is free and open source.")
                    Spacer()
                    Button("Support / Donate ❤️") { openDonationPage() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            apps = TriggerApp.load()
        }
    }

    private var candidates: [TriggerApp] {
        let chosen = Set(apps.map(\.bundleID))
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> TriggerApp? in
                guard let id = app.bundleIdentifier, id != own, !chosen.contains(id), seen.insert(id).inserted else { return nil }
                return TriggerApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: TriggerApp) {
        apps.append(app)
        TriggerApp.save(apps)
    }

    private func remove(_ app: TriggerApp) {
        apps.removeAll { $0 == app }
        TriggerApp.save(apps)
    }

    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
