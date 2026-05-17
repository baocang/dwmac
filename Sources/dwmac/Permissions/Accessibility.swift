import ApplicationServices
import Foundation

enum Accessibility {
    /// Returns true if Accessibility is granted.
    /// If `prompt` is true and not granted, the standard system prompt is shown
    /// directing the user to System Settings → Privacy & Security → Accessibility.
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Print user-facing instructions for granting AX permission.
    static func printInstructions() {
        let bundle = Bundle.main.bundlePath
        let exe = ProcessInfo.processInfo.arguments.first ?? "dwmac"
        FileHandle.standardError.write(Data("""

        ┌──────────────────────────────────────────────────────────────────┐
        │ dwmac needs Accessibility permission to manage windows.          │
        │                                                                  │
        │ Open  System Settings  →  Privacy & Security  →  Accessibility   │
        │ Toggle on the entry for:                                         │
        │   \(exe)
        │                                                                  │
        │ The LaunchAgent will retry automatically every 10 seconds.       │
        └──────────────────────────────────────────────────────────────────┘
        (bundle path: \(bundle))

        """.utf8))
    }
}
