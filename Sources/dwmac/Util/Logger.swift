import Foundation

enum LogLevel: String, Codable, Comparable {
    case debug, info, warn, error

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rank < b.rank }
}

enum Log {
    static var level: LogLevel = .info

    static func debug(_ msg: @autoclosure () -> String) { emit(.debug, msg()) }
    static func info(_ msg: @autoclosure () -> String)  { emit(.info,  msg()) }
    static func warn(_ msg: @autoclosure () -> String)  { emit(.warn,  msg()) }
    static func error(_ msg: @autoclosure () -> String) { emit(.error, msg()) }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func emit(_ lvl: LogLevel, _ msg: String) {
        guard lvl >= level else { return }
        let line = "\(formatter.string(from: Date())) [\(lvl.rawValue)] \(msg)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
