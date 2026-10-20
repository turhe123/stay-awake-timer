import SwiftUI
import AppKit

/// Requests notification permission at launch when session-end notifications are enabled.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: Prefs.notifyOnEnd) as? Bool ?? true {
            AwakeController.requestNotificationPermission()
        }
    }
}

/// Entry point: a menu bar extra plus the Settings and custom-duration windows.
@main
struct StayAwakeTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = AwakeController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(controller)
        }

        Window("Custom Duration", id: "custom") {
            CustomDurationView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar icon: an empty cup when idle, a filled cup with time left when active.
struct MenuBarLabel: View {
    @ObservedObject var controller: AwakeController

    var body: some View {
        if let remaining = controller.remainingText {
            Image(systemName: "cup.and.saucer.fill")
            Text(remaining)
        } else {
            Image(systemName: controller.isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
    }
}
