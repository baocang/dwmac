import Cocoa
import Foundation

// MARK: - Boot

let config = Config.loadOrCreate()
Log.level = config.logLevel
Log.info("dwmac starting (modifier=\(config.modifier.map(\.rawValue).joined(separator: "+")), workspaces=\(config.workspaceCount))")

// Permission gate. Silent check — we do NOT pass prompt:true, because the
// LaunchAgent retries every 10 s and would otherwise spam the system prompt
// once per retry. The user grants permission once in System Settings.
if !Accessibility.isTrusted(prompt: false) {
    Accessibility.printInstructions()
    Log.error("Accessibility permission not granted — exiting silently (LaunchAgent will retry).")
    exit(78) // EX_CONFIG
}
Log.info("Accessibility permission confirmed.")

// NSApplication must exist so we get NSWorkspace + run loop events.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let engine = Engine(config: config)
engine.bootstrap()
Commands.registerAll(engine: engine, config: config)

// Signal handling — clean shutdown on SIGTERM / SIGINT.
signal(SIGTERM) { _ in
    Log.info("SIGTERM — shutting down.")
    HotkeyManager.shared.unregisterAll()
    exit(0)
}
signal(SIGINT) { _ in
    Log.info("SIGINT — shutting down.")
    HotkeyManager.shared.unregisterAll()
    exit(0)
}

Log.info("dwmac ready.")
app.run()
