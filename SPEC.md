# StayAwakeTimer — specification

**Tagline:** Keep your Mac awake for a chosen time, until a download ends, or while certain apps run, from the menu bar.

**Category:** Battery & Power

**Inspired by (paid):** Lungo ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, IOKit, UserNotifications, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Lungo is a small menu bar app on the Mac App Store, priced at about 4.99 dollars, that prevents the Mac from sleeping for set durations, and it earns very good reviews among the many caffeine style tools such as Amphetamine and Caffeine. People pay for the extra triggers and polished design. Our free clean-room version provides durations, triggers and battery safety.

Feature set: One click toggles staying awake indefinitely. The menu offers timed sessions of 15 minutes, 30 minutes, 1, 2, 4 and 8 hours, and a custom time. Trigger rules start staying awake automatically while chosen apps are running, while the Mac is on power adapter, or while an external display is connected. A battery guard stops the session when the charge falls below a chosen percent. An option allows the display to sleep while the system stays awake. The icon shows a filled cup when active with the remaining time in the menu bar title. A notification announces when a session ends.

UI spec: MenuBarExtra with a cup symbol. The menu has the main toggle, the duration list with a checkmark on the active one, a section for triggers with toggles, and Settings. Settings includes the app trigger list with an add button choosing from running apps, the battery guard slider, the display sleep toggle, the notification toggle, and launch at login. Empty state for triggers reads no apps chosen. The title shows time left like 1h 12m only when a timer is running.

Technical approach: Create power assertions with IOPMAssertionCreateWithName using the types kIOPMAssertionTypePreventUserIdleSystemSleep and, when the display must stay on, kIOPMAssertionTypePreventUserIdleDisplaySleep, with a readable reason string, and release them with IOPMAssertionRelease. Track the remaining time with a Timer using an end date. Detect running apps through NSWorkspace launch and terminate notifications plus an initial scan of runningApplications. Battery state is read with IOPSCopyPowerSourcesInfo and an IOPSNotificationCreateRunLoopSource callback for changes, and the power adapter state comes from the same dictionary. External displays are detected by NSScreen count changes through the screen parameters notification. Preferences are stored in AppStorage. Notifications use UserNotifications and launch at login uses SMAppService. No special permissions are required.

Edge cases and error handling: If assertion creation fails, show an alert with the IOReturn code. Closing the lid on a laptop without an external display still sleeps the machine and the app explains this in the settings footer. On quit, release all assertions. After a relaunch, timers are not restored by default to avoid surprises. If multiple triggers overlap, a single assertion is kept until all reasons end. Clock changes are handled by relying on the end date. About 300 lines.
