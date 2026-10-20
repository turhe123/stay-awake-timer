import SwiftUI
import AppKit

/// Opens the project's donation page.
func openDonationPage() {
    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
}

/// The drop-down menu: main toggle, preset durations, trigger toggles and app actions.
struct MenuContent: View {
    @EnvironmentObject private var controller: AwakeController
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.appTriggerOn) private var appTriggerOn = false
    @AppStorage(Prefs.powerTriggerOn) private var powerTriggerOn = false
    @AppStorage(Prefs.displayTriggerOn) private var displayTriggerOn = false

    private let presets: [(String, Int)] = [
        ("15 Minutes", 15), ("30 Minutes", 30), ("1 Hour", 60),
        ("2 Hours", 120), ("4 Hours", 240), ("8 Hours", 480),
    ]

    var body: some View {
        Button(controller.session == .off ? "Stay Awake Indefinitely" : "Turn Off") {
            controller.toggleIndefinite()
        }
        .keyboardShortcut("a")

        Text(statusLine)

        Divider()
        Section("Stay Awake For") {
            ForEach(presets, id: \.1) { title, minutes in
                Toggle(title, isOn: Binding(
                    get: { controller.activeMinutes == minutes },
                    set: { $0 ? controller.start(minutes: minutes) : controller.stop(notify: false) }
                ))
            }
            Button("Custom…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "custom")
            }
        }

        Divider()
        Section("Triggers") {
            Toggle("While Chosen Apps Run", isOn: $appTriggerOn)
            Toggle("While on Power Adapter", isOn: $powerTriggerOn)
            Toggle("While External Display Connected", isOn: $displayTriggerOn)
        }

        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") { openDonationPage() }
        Divider()
        Button("Quit StayAwakeTimer") {
            controller.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusLine: String {
        if let remaining = controller.remainingText { return "Awake — \(remaining) left" }
        if controller.isAwake {
            return "Awake — " + (controller.activeReasons.first ?? "active")
        }
        return "Mac can sleep normally"
    }
}

/// Small window for choosing an arbitrary session length.
struct CustomDurationView: View {
    @EnvironmentObject private var controller: AwakeController
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 1
    @State private var minutes = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep your Mac awake for:").font(.headline)
            Stepper("\(hours) hour\(hours == 1 ? "" : "s")", value: $hours, in: 0...24)
            Stepper("\(minutes) minute\(minutes == 1 ? "" : "s")", value: $minutes, in: 0...55, step: 5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    controller.start(minutes: hours * 60 + minutes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hours * 60 + minutes == 0)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}
