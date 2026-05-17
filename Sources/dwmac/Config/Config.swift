import Foundation

enum ModifierToken: String, Codable, CaseIterable {
    case control, command, option, shift
}

struct Config: Codable {
    var modifier: [ModifierToken]
    /// Fraction of screen width the **left** pane occupies (wide-screen only).
    var leftFraction: Double
    /// Fraction of screen width the **center** pane occupies (wide-screen only).
    var centerFraction: Double
    /// Fraction of screen width the **right** pane occupies (wide-screen only).
    var rightFraction: Double
    /// Outer gap from screen edge.
    var outerGap: Double
    /// Vertical gap (unused in 3-pane mode but kept for future).
    var innerGap: Double
    /// Number of dwmac virtual workspaces per screen.
    var workspaceCount: Int
    /// Bundle IDs that dwmac never tiles — left in place.
    var floatBundleIDs: [String]
    /// Bundle IDs that dwmac ignores entirely — never tracked.
    var ignoreBundleIDs: [String]
    var logLevel: LogLevel
    /// Width:height aspect ratio at or above which a screen is considered
    /// "wide" and gets the three-pane layout. Below this threshold (and on
    /// built-in displays regardless of aspect), the **monocle** layout is
    /// used: every window takes the full visible frame, centered.
    var wideMinAspectRatio: Double

    static let `default` = Config(
        modifier: [.control, .command],
        leftFraction: 0.40,
        centerFraction: 0.50,
        rightFraction: 0.40,
        outerGap: 16,
        innerGap: 6,
        workspaceCount: 9,
        floatBundleIDs: [
            // System dialogs / utilities that don't tile well.
            "com.apple.systempreferences",           // System Preferences (pre-macOS 13)
            "com.apple.systemsettings",              // System Settings (macOS 13+)
            "com.apple.ScreenSaver.Engine",          // screensaver
            "com.apple.installer",                   // Installer.app
            "com.apple.calculator",                  // Calculator
            "com.apple.PrintCenter",                 // Print Center
            "com.apple.archiveutility",              // Archive Utility
            "com.apple.FontBook",                    // Font Book
            "com.apple.audio.AudioMIDISetup",        // Audio MIDI Setup
            "com.apple.Stickies",                    // Stickies
            "com.apple.ActivityMonitor",             // Activity Monitor
            "com.apple.ColorSyncUtility",            // ColorSync Utility
            "com.apple.DigitalColorMeter",           // Digital Color Meter
            "com.apple.PhotoBooth"                   // Photo Booth (often goes weird with size)
        ],
        ignoreBundleIDs: [],
        logLevel: .info,
        wideMinAspectRatio: 2.0
    )

    static func loadOrCreate() -> Config {
        let url = configURL()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        } catch {
            Log.warn("could not create config dir: \(error)")
        }
        guard fm.fileExists(atPath: url.path) else {
            do {
                try writeDefault(to: url)
                Log.info("wrote default config to \(url.path)")
            } catch {
                Log.warn("could not write default config: \(error)")
            }
            return .default
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            return decoded.validated()
        } catch {
            Log.warn("config parse failed (\(error)) — falling back to defaults")
            return .default
        }
    }

    static func configURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/dwmac/config.json")
    }

    private static func writeDefault(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(Config.default)
        try data.write(to: url, options: .atomic)
    }

    func validated() -> Config {
        var c = self
        c.leftFraction   = Geometry.clamp(c.leftFraction,   0.10, 0.60)
        c.centerFraction = Geometry.clamp(c.centerFraction, 0.20, 0.80)
        c.rightFraction  = Geometry.clamp(c.rightFraction,  0.10, 0.60)
        c.outerGap = Geometry.clamp(c.outerGap, 0, 64)
        c.innerGap = Geometry.clamp(c.innerGap, 0, 64)
        c.workspaceCount = Geometry.clamp(c.workspaceCount, 1, 9)
        c.wideMinAspectRatio = Geometry.clamp(c.wideMinAspectRatio, 1.0, 6.0)
        if c.modifier.isEmpty { c.modifier = [.control, .command] }
        return c
    }
}

/// Custom decoder: every field is optional and falls back to the default if
/// missing or invalid. Legacy keys from older versions are silently ignored.
extension Config {
    private enum DecodeKeys: String, CodingKey {
        case modifier
        case leftFraction, centerFraction, rightFraction
        case sideFraction   // legacy: still accepted as a fallback for left/right
        case outerGap, innerGap
        case workspaceCount
        case floatBundleIDs, ignoreBundleIDs
        case logLevel
        case wideMinAspectRatio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodeKeys.self)
        let def = Config.default
        modifier        = (try? c.decode([ModifierToken].self, forKey: .modifier)) ?? def.modifier
        centerFraction  = (try? c.decode(Double.self, forKey: .centerFraction))   ?? def.centerFraction
        // Legacy `sideFraction` is the fallback when only one side value
        // was set in older config files; explicit left/right always win.
        let legacySide  = (try? c.decode(Double.self, forKey: .sideFraction))     ?? def.leftFraction
        leftFraction    = (try? c.decode(Double.self, forKey: .leftFraction))     ?? legacySide
        rightFraction   = (try? c.decode(Double.self, forKey: .rightFraction))    ?? legacySide
        outerGap        = (try? c.decode(Double.self, forKey: .outerGap))         ?? def.outerGap
        innerGap        = (try? c.decode(Double.self, forKey: .innerGap))         ?? def.innerGap
        workspaceCount  = (try? c.decode(Int.self,    forKey: .workspaceCount))   ?? def.workspaceCount
        floatBundleIDs  = (try? c.decode([String].self, forKey: .floatBundleIDs)) ?? def.floatBundleIDs
        ignoreBundleIDs = (try? c.decode([String].self, forKey: .ignoreBundleIDs)) ?? def.ignoreBundleIDs
        logLevel        = (try? c.decode(LogLevel.self, forKey: .logLevel))       ?? def.logLevel
        wideMinAspectRatio = (try? c.decode(Double.self, forKey: .wideMinAspectRatio)) ?? def.wideMinAspectRatio
    }
}
