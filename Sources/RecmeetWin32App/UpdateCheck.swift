#if os(Windows)
import WinSDK
import Foundation
import RecmeetCore
import RecmeetCoreWindows

let WM_UPDATE_AVAILABLE: UINT = UINT(WM_USER) + 5

/// Box that survives the worker → main thread handshake.
final class PendingUpdate {
    var release: ReleaseInfo?
}
let pendingUpdate = PendingUpdate()

/// Kicked off from main.swift after the window is up. Silently does nothing
/// if the user has no internet, the API rate-limits us, or the latest
/// release isn't newer.
func startUpdateCheck(parent: HWND?) {
    Task.detached {
        do {
            guard let release = try await Updater.fetchLatestRelease(),
                  Updater.isNewer(release) else { return }
            pendingUpdate.release = release
            _ = PostMessageW(parent, WM_UPDATE_AVAILABLE, 0, 0)
        } catch {
            // No connection or transient failure — say nothing.
        }
    }
}

func handleUpdateAvailable(parent: HWND?) {
    guard let release = pendingUpdate.release else { return }
    pendingUpdate.release = nil

    let title = "Update available"
    let body = """
    recmeet \(release.tagName) is available.
    You're on \(RECMEET_CURRENT_VERSION).

    Update now? recmeet will download the new version, swap it in, and relaunch.
    """

    let response = title.withWide { wt in
        body.withWide { wb in
            MessageBoxW(parent, wb, wt,
                        UINT(MB_YESNO | MB_ICONINFORMATION))
        }
    }
    if response == IDYES {
        applyUpdate(parent: parent, release: release)
    }
}

private func applyUpdate(parent: HWND?, release: ReleaseInfo) {
    guard let asset = release.windowsAssetURL else {
        showError(parent, "This release has no Windows binary.")
        return
    }
    // Resolve the path of the running executable so the update.bat knows
    // which file to overwrite.
    var buf = [WCHAR](repeating: 0, count: 1024)
    let n = GetModuleFileNameW(nil, &buf, DWORD(buf.count))
    guard n > 0 else {
        showError(parent, "Couldn't determine the running executable path.")
        return
    }
    let exePath = String(decoding: buf.prefix(Int(n)), as: UTF16.self)

    Task.detached {
        do {
            let zip = try await WindowsUpdateApplier.download(asset)
            try WindowsUpdateApplier.applyAndRelaunch(zipPath: zip, currentExePath: exePath)
            // applyAndRelaunch calls exit(0).
        } catch {
            let msg = "Update failed: \(error.localizedDescription)"
            await Task { @MainActor in showError(parent, msg) }.value
        }
    }
}

private func showError(_ parent: HWND?, _ message: String) {
    "Update".withWide { wt in
        message.withWide { wm in
            _ = MessageBoxW(parent, wm, wt, UINT(MB_OK | MB_ICONWARNING))
        }
    }
}
#endif
