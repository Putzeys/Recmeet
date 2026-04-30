import Foundation
import SwiftUI
import AppKit
import RecmeetCore
import RecmeetCoreApple

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var available: ReleaseInfo?
    @Published var isApplying = false
    @Published var errorMessage: String?

    private static let skipKey = "skippedUpdateVersion"

    func checkOnLaunch() {
        Task { await checkOnce() }
    }

    func checkOnce() async {
        do {
            guard let release = try await Updater.fetchLatestRelease(),
                  Updater.isNewer(release) else { return }
            // Skip versions the user has already dismissed.
            if let skipped = UserDefaults.standard.string(forKey: Self.skipKey),
               skipped == release.tagName {
                return
            }
            available = release
        } catch {
            // Silent fail on launch — no internet shouldn't bother the user.
        }
    }

    func skipThisVersion() {
        if let r = available {
            UserDefaults.standard.set(r.tagName, forKey: Self.skipKey)
        }
        available = nil
    }

    func dismiss() {
        available = nil
    }

    func applyNow() {
        guard let release = available, let asset = release.macAssetURL else {
            errorMessage = "This release has no macOS asset attached."
            return
        }
        isApplying = true
        errorMessage = nil
        Task {
            do {
                let zip = try await AppleUpdateApplier.download(asset)
                try AppleUpdateApplier.applyAndRelaunch(zipPath: zip)
                // applyAndRelaunch calls exit(0) — we never get here.
            } catch {
                errorMessage = "Update failed: \(error.localizedDescription)"
                isApplying = false
            }
        }
    }
}
