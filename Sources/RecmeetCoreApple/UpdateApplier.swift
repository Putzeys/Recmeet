import Foundation
import RecmeetCore

public enum AppleUpdateApplier {

    /// Downloads `url` to `~/Library/Caches/recmeet/update.zip`, returns local URL.
    public static func download(_ url: URL) async throws -> URL {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("recmeet")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dest = cacheDir.appendingPathComponent("update.zip")
        try? FileManager.default.removeItem(at: dest)

        let (tmp, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Unzips, then spawns a detached shell that waits for us to exit, swaps
    /// `/Applications/recmeet.app`, and relaunches. Calls `exit(0)` so the
    /// running app terminates immediately.
    public static func applyAndRelaunch(zipPath: URL) throws -> Never {
        let stagingDir = zipPath.deletingLastPathComponent().appendingPathComponent("extract")
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.launchPath = "/usr/bin/unzip"
        unzip.arguments = ["-q", zipPath.path, "-d", stagingDir.path]
        try unzip.run()
        unzip.waitUntilExit()

        let newApp = stagingDir.appendingPathComponent("recmeet.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw NSError(
                domain: "recmeet.update",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "recmeet.app not found in update zip"]
            )
        }

        let target = "/Applications/recmeet.app"
        let script = """
        sleep 1
        rm -rf "\(target)"
        mv "\(newApp.path)" "\(target)"
        open "\(target)"
        """

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        try task.run()

        // Don't wait — we're about to exit so the swap can complete.
        exit(0)
    }
}
