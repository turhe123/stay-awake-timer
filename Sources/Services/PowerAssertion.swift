import Foundation
import IOKit.pwr_mgt

/// Owns the IOKit power assertions that keep the system (and optionally the display) awake.
/// Only one assertion of each type is ever held, no matter how many reasons are active.
final class PowerAssertion {
    enum AssertionError: Error, LocalizedError {
        case creationFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .creationFailed(let code):
                return String(format: "IOPMAssertionCreateWithName failed with IOReturn 0x%08X (%d).", UInt32(bitPattern: code), code)
            }
        }
    }

    private var systemID: IOPMAssertionID?
    private var displayID: IOPMAssertionID?

    var isHeld: Bool { systemID != nil }

    /// Ensures the requested assertions are held (or released). Throws if creation fails.
    func update(active: Bool, keepDisplayOn: Bool, reason: String) throws {
        guard active else { releaseAll(); return }
        if systemID == nil {
            systemID = try create(kIOPMAssertionTypePreventUserIdleSystemSleep, reason: reason)
        }
        if keepDisplayOn, displayID == nil {
            displayID = try create(kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: reason)
        } else if !keepDisplayOn, let id = displayID {
            IOPMAssertionRelease(id)
            displayID = nil
        }
    }

    func releaseAll() {
        if let id = systemID { IOPMAssertionRelease(id) }
        if let id = displayID { IOPMAssertionRelease(id) }
        systemID = nil
        displayID = nil
    }

    private func create(_ type: String, reason: String) throws -> IOPMAssertionID {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString,
                                                 &id)
        guard result == kIOReturnSuccess else { throw AssertionError.creationFailed(result) }
        return id
    }

    deinit { releaseAll() }
}
