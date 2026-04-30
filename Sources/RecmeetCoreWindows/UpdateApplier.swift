#if os(Windows)
import WinSDK
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import RecmeetCore

/// Append-only log used by the updater so failures are visible after the app
/// has already exited. Lives at `%LOCALAPPDATA%\recmeet\update.log`.
final class UpdateLog {
    private let url: URL

    init() {
        let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: base).appendingPathComponent("recmeet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("update.log")
    }

    func write(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            _ = try? h.write(contentsOf: data)
            _ = try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    var path: String { url.path }
}

public enum WindowsUpdateApplier {

    public static func download(_ url: URL) async throws -> URL {
        let log = UpdateLog()
        log.write("download() begin: \(url.absoluteString)")

        let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"]
            ?? NSTemporaryDirectory()
        let cacheDir = URL(fileURLWithPath: base).appendingPathComponent("recmeet")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dest = cacheDir.appendingPathComponent("update.zip")
        try? FileManager.default.removeItem(at: dest)

        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse {
            log.write("download HTTP \(http.statusCode)")
        }
        try FileManager.default.moveItem(at: tmp, to: dest)

        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] ?? "?"
        log.write("download() done: \(dest.path) (\(size) bytes)")
        return dest
    }

    public static func applyAndRelaunch(zipPath: URL, currentExePath: String) throws -> Never {
        let log = UpdateLog()
        log.write("applyAndRelaunch() begin")
        log.write("  zip: \(zipPath.path)")
        log.write("  currentExe: \(currentExePath)")

        let stagingDir = zipPath.deletingLastPathComponent().appendingPathComponent("extract")
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        log.write("  staging: \(stagingDir.path)")

        // tar.exe ships with Windows 10/11 and handles .zip natively.
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\tar.exe")
        tar.arguments = ["-xf", zipPath.path, "-C", stagingDir.path]
        try tar.run()
        tar.waitUntilExit()
        log.write("  tar exit code: \(tar.terminationStatus)")

        let listing = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
        log.write("  staging contents: \(listing)")

        let newExe = stagingDir.appendingPathComponent("recmeet.exe")
        guard FileManager.default.fileExists(atPath: newExe.path) else {
            log.write("ERROR: recmeet.exe missing in extracted zip")
            throw NSError(
                domain: "recmeet.update",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "recmeet.exe not found in update zip; staging contents: \(listing)"]
            )
        }
        let newSize = (try? FileManager.default.attributesOfItem(atPath: newExe.path))?[.size] ?? "?"
        log.write("  newExe ready: \(newExe.path) (\(newSize) bytes)")

        let batPath = zipPath.deletingLastPathComponent().appendingPathComponent("update.bat")
        let batLogPath = zipPath.deletingLastPathComponent().appendingPathComponent("update-bat.log")

        // cmd.exe doesn't accept forward slashes inside `move` / `start`
        // arguments — those are option markers there. Foundation's URL.path
        // hands us POSIX-style paths on Swift-Windows, so flip every / to \
        // before splicing into the batch.
        let srcPath = newExe.path.replacingOccurrences(of: "/", with: "\\")
        let dstPath = currentExePath.replacingOccurrences(of: "/", with: "\\")
        let logPath = batLogPath.path.replacingOccurrences(of: "/", with: "\\")

        let bat = """
        @echo off
        set LOG=\(logPath)
        echo [bat] start %DATE% %TIME% > "%LOG%"
        echo [bat] sleeping 2s >> "%LOG%"
        timeout /t 2 /nobreak >nul

        echo [bat] move SRC: "\(srcPath)" >> "%LOG%"
        echo [bat] move DST: "\(dstPath)" >> "%LOG%"
        move /y "\(srcPath)" "\(dstPath)" >> "%LOG%" 2>&1
        if errorlevel 1 (
            echo [bat] MOVE FAILED, errorlevel %errorlevel% >> "%LOG%"
            goto :end
        )
        echo [bat] move OK >> "%LOG%"

        echo [bat] launching "\(dstPath)" >> "%LOG%"
        start "" "\(dstPath)"

        :end
        echo [bat] done %DATE% %TIME% >> "%LOG%"
        """
        try bat.write(to: batPath, atomically: true, encoding: .utf8)
        log.write("  wrote bat: \(batPath.path)")
        log.write("  bat log will be: \(batLogPath.path)")

        // Use ShellExecuteW with the "open" verb — this is the canonical
        // detached-spawn path on Windows. Foundation's Process inherits
        // handles in ways that have bitten us before; ShellExecuteW does
        // not.
        let executeResult = batPath.path.withCString(encodedAs: UTF16.self) { wpath -> Int in
            "open".withCString(encodedAs: UTF16.self) { wverb -> Int in
                let h = ShellExecuteW(nil, wverb, wpath, nil, nil, Int32(SW_SHOWMINIMIZED))
                return Int(bitPattern: h)
            }
        }
        log.write("  ShellExecuteW returned: \(executeResult) (>32 means success)")

        log.write("applyAndRelaunch() exiting now")
        exit(0)
    }
}
#endif
