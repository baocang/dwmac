import Foundation

enum ModifierToken: String, Codable, CaseIterable {
    case control, command, option, shift
}

struct Config: Codable {
    var modifier: [ModifierToken]
    /// Fraction of screen width the center pane occupies.
    var centerFraction: Double
    /// Fraction of screen width each side pane occupies.
    var sideFraction: Double
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
    /// If true, also disable tiling on screens whose width:height ratio is
    /// below `wideMinAspectRatio` even when external. Default false.
    var wideAspectFilter: Bool
    /// Minimum aspect ratio to consider a display "wide enough" when
    /// `wideAspectFilter` is true. Default 1.78 (≈16:9).
    var wideMinAspectRatio: Double
    /// If true, dwmac also tiles built-in (laptop) displays. Default false.
    var manageBuiltin: Bool

    static let `default` = Config(
        modifier: [.control, .command],
        centerFraction: 0.50,
        sideFraction: 0.33,
        outerGap: 8,
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
        wideAspectFilter: false,
        wideMinAspectRatio: 1.78,
        manageBuiltin: false
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
        c.centerFraction = Geometry.clamp(c.centerFraction, 0.20, 0.80)
        c.sideFraction   = Geometry.clamp(c.sideFraction,   0.15, 0.50)
        c.outerGap = Geometry.clamp(c.outerGap, 0, 64)
        c.innerGap = Geometry.clamp(c.innerGap, 0, 64)
        c.workspaceCount = Geometry.clamp(c.workspaceCount, 1, 9)
        c.wideMinAspectRatio = Geometry.clamp(c.wideMinAspectRatio, 1.0, 4.0)
        if c.modifier.isEmpty { c.modifier = [.control, .command] }
        return c
    }
}

/// Custom decoder: every field is optional and falls back to the default if
/// missing or invalid. Legacy keys from older versions are silently ignored.
extension Config {
    private enum DecodeKeys: String, CodingKey {
        case modifier
        case centerFraction, sideFraction
        case outerGap, innerGap
        case workspaceCount
        case floatBundleIDs, ignoreBundleIDs
        case logLevel
        case wideAspectFilter, wideMinAspectRatio
        case manageBuiltin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodeKeys.self)
        let def = Config.default
        modifier        = (try? c.decode([ModifierToken].self, forKey: .modifier)) ?? def.modifier
        centerFraction  = (try? c.decode(Double.self, forKey: .centerFraction))   ?? def.centerFraction
        sideFraction    = (try? c.decode(Double.self, forKey: .sideFraction))     ?? def.sideFraction
        outerGap        = (try? c.decode(Double.self, forKey: .outerGap))         ?? def.outerGap
        innerGap        = (try? c.decode(Double.self, forKey: .innerGap))         ?? def.innerGap
        workspaceCount  = (try? c.decode(Int.self,    forKey: .workspaceCount))   ?? def.workspaceCount
        floatBundleIDs  = (try? c.decode([String].self, forKey: .floatBundleIDs)) ?? def.floatBundleIDs
        ignoreBundleIDs = (try? c.decode([String].self, forKey: .ignoreBundleIDs)) ?? def.ignoreBundleIDs
        logLevel        = (try? c.decode(LogLevel.self, forKey: .logLevel))       ?? def.logLevel
        wideAspectFilter   = (try? c.decode(Bool.self, forKey: .wideAspectFilter))    ?? def.wideAspectFilter
        wideMinAspectRatio = (try? c.decode(Double.self, forKey: .wideMinAspectRatio)) ?? def.wideMinAspectRatio
        manageBuiltin      = (try? c.decode(Bool.self, forKey: .manageBuiltin))       ?? def.manageBuiltin
    }
}
