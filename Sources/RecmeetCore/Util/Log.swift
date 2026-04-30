import Foundation

public enum Log {
    /// Optional callback that mirrors every Log line into platform-specific
    /// sinks (e.g. a file on Windows, where stderr goes nowhere in a
    /// SUBSYSTEM:WINDOWS GUI build).
    public static var sink: ((String) -> Void)?

    public static func info(_ msg: String) {
        FileHandle.standardError.write(Data("[recmeet] \(msg)\n".utf8))
        sink?("info: \(msg)")
    }

    public static func error(_ msg: String) {
        FileHandle.standardError.write(Data("[recmeet][error] \(msg)\n".utf8))
        sink?("error: \(msg)")
    }
}
