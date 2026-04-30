import Foundation

public enum Log {
    /// Optional callback that mirrors every Log line into platform-specific
    /// sinks (e.g. a file on Windows, where stderr goes nowhere in a
    /// SUBSYSTEM:WINDOWS GUI build).
    public static var sink: ((String) -> Void)?

    public static func info(_ msg: String) {
        writeStderr("[recmeet] \(msg)\n")
        sink?("info: \(msg)")
    }

    public static func error(_ msg: String) {
        writeStderr("[recmeet][error] \(msg)\n")
        sink?("error: \(msg)")
    }

    /// Best-effort write to stderr. The legacy `FileHandle.write(_: Data)`
    /// API is non-throwing and `fatalError`s on failure — that crashes
    /// SUBSYSTEM:WINDOWS GUI builds where stderr is closed. The throwing
    /// `write(contentsOf:)` lets us swallow the error silently.
    private static func writeStderr(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
    }
}
