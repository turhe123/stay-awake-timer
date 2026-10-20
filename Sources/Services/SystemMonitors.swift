import AppKit
import CoreGraphics
import IOKit.ps

/// Watches the power source (battery percentage and AC adapter state) via IOPowerSources.
final class PowerSourceMonitor {
    private(set) var batteryPercent: Int?
    private(set) var onACPower = true
    var onChange: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.refresh()
            monitor.onChange?()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        var percent: Int?
        var ac = true
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let type = desc[kIOPSTypeKey] as? String, type != kIOPSInternalBatteryType { continue }
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                percent = cur * 100 / max
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                ac = state == kIOPSACPowerValue
            }
        }
        batteryPercent = percent
        onACPower = ac
    }

    deinit {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }
}

/// Tracks running applications through NSWorkspace launch/terminate notifications.
final class AppMonitor {
    private(set) var runningBundleIDs: Set<String> = []
    var onChange: (() -> Void)?
    private var tokens: [NSObjectProtocol] = []

    init() {
        scan()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scan()
                self?.onChange?()
            })
        }
    }

    private func scan() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    deinit { tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }
}

/// Detects whether an external (non built-in) display is connected.
final class DisplayMonitor {
    private(set) var hasExternalDisplay = false
    var onChange: (() -> Void)?
    private var token: NSObjectProtocol?

    init() {
        scan()
        token = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            self?.scan()
            self?.onChange?()
        }
    }

    private func scan() {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        hasExternalDisplay = NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0
        }
    }

    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
