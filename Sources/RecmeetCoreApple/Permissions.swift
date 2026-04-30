import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreGraphics
import AppKit
import RecmeetCore

public enum Permissions {
    /// Request microphone permission. Blocks until user responds.
    public static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Triggers the Screen Recording prompt. Uses CGRequestScreenCaptureAccess
    /// which forces the native dialog and registers the binary in System Settings.
    public static func ensureScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            // Already granted — proceed.
            return true
        }
        // Not granted: this triggers the system prompt and adds the binary
        // to System Settings → Privacy & Security → Screen Recording.
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            return true
        }
        Log.error("Screen Recording permission required.")
        Log.error("recmeet has been added to System Settings → Privacy & Security → Screen Recording.")
        Log.error("Toggle it ON, then re-run this command.")
        return false
    }

    /// Whether the microphone permission has already been explicitly denied.
    public static func microphoneDenied() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }

    /// Open System Settings directly on the Microphone pane.
    public static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings directly on the Screen Recording pane.
    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
