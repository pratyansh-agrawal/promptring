// ════════════════════════════════════════════════════════════════════
//  Promptring — notification agent
// ════════════════════════════════════════════════════════════════════
//  A minimal macOS .app bundle whose only job is to post a desktop
//  notification banner. Shipped as a signed .app with its own bundle
//  identifier, it has a real notification identity — so banners appear
//  reliably from ANY terminal (Terminal.app, iTerm2, VS Code, tmux…) or
//  from no terminal at all. This is the piece a bare CLI / osascript
//  cannot provide.
//
//  Uses the modern UNUserNotificationCenter API, which (unlike the
//  legacy NSUserNotification) still presents on-screen banners on recent
//  macOS. Key details learned the hard way:
//    • The bundle must be REGISTERED with LaunchServices and AUTHORIZED;
//      the very first launch shows a one-time permission prompt → Allow.
//    • The process must stay alive a few seconds after handing off the
//      notification — exiting immediately cancels banner presentation.
//    • interruptionLevel .active keeps it a normal, visible banner.
//
//  Usage:
//      Promptring.app/Contents/MacOS/promptring \
//          --title "✅ Copilot" --subtitle "Task complete" --message "…"
//
//  Sound is left to the caller (copilot-notify plays the bundled sound
//  via afplay), so this stays a pure, silent banner poster.
// ════════════════════════════════════════════════════════════════════

import Foundation
import Cocoa
import UserNotifications

// ── parse --key value arguments ─────────────────────────────────────
func arg(_ key: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: key), i + 1 < a.count { return a[i + 1] }
    return nil
}

let title    = arg("--title")    ?? "Copilot"
let subtitle = arg("--subtitle") ?? ""
let message  = arg("--message")  ?? ""

// Forces the banner to present even while our own app is foreground.
final class Delegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                willPresent n: UNNotification,
                                withCompletionHandler h:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .list])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)        // no Dock icon / menu bar

let delegate = Delegate()
let center = UNUserNotificationCenter.current()
center.delegate = delegate

center.requestAuthorization(options: [.alert, .sound]) { _, _ in
    let content = UNMutableNotificationContent()
    content.title = title
    if !subtitle.isEmpty { content.subtitle = subtitle }
    if !message.isEmpty  { content.body = message }
    content.sound = nil                     // caller plays sound via afplay
    content.interruptionLevel = .active

    let request = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
    center.add(request) { _ in
        // Stay alive long enough for the system to draw the banner;
        // exiting too early cancels presentation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// Safety net: never hang indefinitely — quit after at most 8s regardless.
DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
    NSApplication.shared.terminate(nil)
}

app.run()
