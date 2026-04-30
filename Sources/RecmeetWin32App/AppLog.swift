#if os(Windows)
import Foundation

private let appLogURL: URL = {
    let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? NSTemporaryDirectory()
    let dir = URL(fileURLWithPath: base).appendingPathComponent("recmeet")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("app.log")
}()

private let appLogLock = NSLock()

/// Append a line to `%LOCALAPPDATA%\recmeet\app.log`. **Synchronous** — if the
/// next line crashes, we still have everything up to the previous one on disk.
func appLog(_ msg: String) {
    appLogLock.lock()
    defer { appLogLock.unlock() }
    let line = "[\(Date())] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: appLogURL) {
        _ = try? h.seekToEnd()
        _ = try? h.write(contentsOf: data)
        _ = try? h.close()
    } else {
        try? data.write(to: appLogURL)
    }
}

func appLogPath() -> String { appLogURL.path }
#endif
