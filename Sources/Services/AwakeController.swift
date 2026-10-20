import AppKit
import Combine
import UserNotifications

/// UserDefaults keys shared by the controller and the SwiftUI views.
enum Prefs {
    static let triggerApps = "triggerApps"
    static let appTriggerOn = "appTriggerOn"
    static let powerTriggerOn = "powerTriggerOn"
    static let displayTriggerOn = "displayTriggerOn"
    static let batteryGuard = "batteryGuardPercent"   // 0 = off
    static let allowDisplaySleep = "allowDisplaySleep"
    static let notifyOnEnd = "notifyOnEnd"
}

/// An application chosen by the user as an "awake while running" trigger.
struct TriggerApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }

    static func load() -> [TriggerApp] {
        guard let data = UserDefaults.standard.data(forKey: Prefs.triggerApps) else { return [] }
        return (try? JSONDecoder().decode([TriggerApp].self, from: data)) ?? []
    }

    static func save(_ apps: [TriggerApp]) {
        if let data = try? JSONEncoder().encode(apps) { UserDefaults.standard.set(data, forKey: Prefs.triggerApps) }
    }
}

/// Central state machine: combines the manual session and the trigger rules into a single
/// "should stay awake" decision, enforces the battery guard and drives the power assertion.
@MainActor
final class AwakeController: ObservableObject {
    enum Session: Equatable {
        case off
        case indefinite
        case timed(end: Date, minutes: Int)
    }

    @Published private(set) var session: Session = .off
    @Published private(set) var isAwake = false
    @Published private(set) var remainingText: String?
    @Published private(set) var activeReasons: [String] = []

    private let assertion = PowerAssertion()
    private let power = PowerSourceMonitor()
    private let apps = AppMonitor()
    private let displays = DisplayMonitor()
    private var ticker: Timer?
    private var defaultsObserver: AnyCancellable?
    private var terminateObserver: AnyCancellable?
    private var guardTripped = false
    private var lastErrorShown: IOReturn?

    init() {
        UserDefaults.standard.register(defaults: [Prefs.notifyOnEnd: true, Prefs.batteryGuard: 0])
        let refresh: () -> Void = { [weak self] in Task { @MainActor in self?.evaluate() } }
        power.onChange = refresh
        apps.onChange = refresh
        displays.onChange = refresh
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
        // Release all assertions on quit so the Mac is never left awake by accident.
        terminateObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.shutdown() }
        evaluate()
    }

    var batteryPercent: Int? { power.batteryPercent }
    var activeMinutes: Int? { if case .timed(_, let m) = session { return m }; return nil }

    // MARK: Manual session

    func toggleIndefinite() {
        session == .off ? start(minutes: nil) : stop(notify: false)
    }

    func start(minutes: Int?) {
        guardTripped = false
        if let minutes, minutes > 0 {
            session = .timed(end: Date().addingTimeInterval(TimeInterval(minutes * 60)), minutes: minutes)
            startTicker()
        } else {
            session = .indefinite
            stopTicker()
        }
        evaluate()
    }

    func stop(notify: Bool, reason: String = "Your Mac may now sleep normally.") {
        let wasActive = session != .off
        session = .off
        stopTicker()
        evaluate()
        if notify && wasActive { postNotification(title: "Stay-awake session ended", body: reason) }
    }

    func shutdown() {
        stopTicker()
        assertion.releaseAll()
    }

    // MARK: Evaluation

    private func evaluate() {
        let d = UserDefaults.standard
        var reasons: [String] = []

        if case .timed(let end, _) = session, end <= Date() {
            stop(notify: true, reason: "Your timed session is over.")
            return
        }
        if session != .off { reasons.append("Manual session") }

        if d.bool(forKey: Prefs.appTriggerOn) {
            let running = TriggerApp.load().filter { apps.runningBundleIDs.contains($0.bundleID) }
            reasons += running.map { "\($0.name) is running" }
        }
        if d.bool(forKey: Prefs.powerTriggerOn), power.onACPower, power.batteryPercent != nil {
            reasons.append("Power adapter connected")
        }
        if d.bool(forKey: Prefs.displayTriggerOn), displays.hasExternalDisplay {
            reasons.append("External display connected")
        }

        // Battery guard: on battery and below the threshold, end everything.
        let threshold = d.integer(forKey: Prefs.batteryGuard)
        if threshold > 0, !power.onACPower, let pct = power.batteryPercent, pct < threshold {
            if !reasons.isEmpty && !guardTripped {
                guardTripped = true
                if session != .off {
                    session = .off
                    stopTicker()
                }
                postNotification(title: "Battery guard", body: "Battery is at \(pct)%. Your Mac may sleep again.")
            }
            reasons = []
        } else {
            guardTripped = false
        }

        activeReasons = reasons
        apply(active: !reasons.isEmpty, allowDisplaySleep: d.bool(forKey: Prefs.allowDisplaySleep))
        updateRemaining()
    }

    private func apply(active: Bool, allowDisplaySleep: Bool) {
        do {
            try assertion.update(active: active, keepDisplayOn: !allowDisplaySleep,
                                 reason: "StayAwakeTimer: \(activeReasons.joined(separator: ", "))")
            lastErrorShown = nil
        } catch {
            assertion.releaseAll()
            if case PowerAssertion.AssertionError.creationFailed(let code) = error, lastErrorShown != code {
                lastErrorShown = code
                showAlert(error.localizedDescription)
            }
        }
        isAwake = assertion.isHeld
    }

    // MARK: Timer

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        remainingText = nil
    }

    private func tick() {
        if case .timed(let end, _) = session, end <= Date() {
            evaluate()
        } else {
            updateRemaining()
        }
    }

    private func updateRemaining() {
        guard case .timed(let end, _) = session else { remainingText = nil; return }
        let text = Self.format(end.timeIntervalSinceNow)
        if text != remainingText { remainingText = text }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    // MARK: Feedback

    private func postNotification(title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: Prefs.notifyOnEnd) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't keep your Mac awake"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
