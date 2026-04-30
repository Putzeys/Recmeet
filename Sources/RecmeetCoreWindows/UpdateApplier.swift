#if os(Windows)
import WinSDK
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import RecmeetCore

public enum WindowsUpdateApplier {

    /// Downloads `url` into `%LOCALAPPDATA%\recmeet\update.zip` and returns
    /// the file URL. Replaces any previous update file.
    public static func download(_ url: URL) async throws -> URL {
        let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"]
            ?? NSTemporaryDirectory()
        let cacheDir = URL(fileURLWithPath: base).appendingPathComponent("recmeet")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dest = cacheDir.appendingPathComponent("update.zip")
        try? FileManager.default.removeItem(at: dest)

        let (tmp, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Extracts the zip, writes a one-shot update.bat that waits for us to
    /// exit, moves the new exe over the running one, relaunches it, and
    /// deletes itself. Calls `exit(0)` so the bat's wait can succeed.
    public static func applyAndRelaunch(zipPath: URL, currentExePath: String) throws -> Never {
        let stagingDir = zipPath.deletingLastPathComponent().appendingPathComponent("extract")
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // tar.exe ships with Windows 10/11 and handles .zip natively.
        let tar = Process()
        tar.launchPath = "C:\\Windows\\System32\\tar.exe"
        tar.arguments = ["-xf", zipPath.path, "-C", stagingDir.path]
        try tar.run()
        tar.waitUntilExit()

        let newExe = stagingDir.appendingPathComponent("recmeet.exe")
        guard FileManager.default.fileExists(atPath: newExe.path) else {
            throw NSError(
                domain: "recmeet.update",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "recmeet.exe not found in update zip"]
            )
        }

        let batPath = zipPath.deletingLastPathComponent().appendingPathComponent("update.bat")
        let bat = """
        @echo off
        timeout /t 2 /nobreak >nul
        move /y "\(newExe.path)" "\(currentExePath)" >nul
        start "" "\(currentExePath)"
        del "%~f0"
        """
        try bat.write(to: batPath, atomically: true, encoding: .utf8)

        // Spawn the bat detached so it survives our exit. `start` opens it
        // in a new (briefly-visible) console that closes itself.
        let cmd = Process()
        cmd.launchPath = "C:\\Windows\\System32\\cmd.exe"
        cmd.arguments = ["/c", "start", "", "/min", batPath.path]
        try cmd.run()

        exit(0)
    }
}
#endif
