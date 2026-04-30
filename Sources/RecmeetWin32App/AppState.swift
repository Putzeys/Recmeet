#if os(Windows)
import WinSDK
import Foundation
import RecmeetCore
import RecmeetCoreWindows

/// Process-wide state for the recmeet Win32 GUI. The window class WNDPROC is
/// `@convention(c)` so it can't capture context — instead it reads from this
/// global. Single-window app, so a global is fine here.
final class AppState {
    // Configuration
    var captureMic: Bool = true
    var captureSystem: Bool = true
    var gainPercent: Int = 100             // 0–200
    var outputDir: URL = defaultOutputDir()

    // Mix configuration (used after stop, when both sources captured).
    var micMixPercent: Int = 100           // 0–100
    var systemMixPercent: Int = 100        // 0–100
    var keepSeparateTracks: Bool = false

    var devices: [AudioInputDevice] = []
    var selectedDeviceIndex: Int = 0

    // Recording lifecycle
    var mic: MicRecorder?
    var system: SystemRecorder?
    var isRecording: Bool = false
    var hasRecordedSession: Bool = false   // post-stop, awaiting mix decision
    var bothCapturedInLastSession: Bool = false
    var isMixing: Bool = false
    var startTime: Date?
    var sessionPath: URL?
    var mergedFile: URL?
    var statusText: String = "Ready."

    // Control HWNDs (set during WM_CREATE).
    var hwndMain: HWND?
    var hwndMicCheck: HWND?
    var hwndSysCheck: HWND?
    var hwndDeviceCombo: HWND?
    var hwndGainSlider: HWND?
    var hwndGainLabel: HWND?
    var hwndOutputLabel: HWND?
    var hwndOpenFolderBtn: HWND?
    var hwndRecordBtn: HWND?
    var hwndDontMergeBtn: HWND?
    var hwndStatusLabel: HWND?
    var hwndElapsedLabel: HWND?

    var hwndMicMixSlider: HWND?
    var hwndMicMixLabel: HWND?
    var hwndSysMixSlider: HWND?
    var hwndSysMixLabel: HWND?
    var hwndKeepTracksCheck: HWND?

    init() {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        devices = AudioDevices.listInputs()
        if let i = devices.firstIndex(where: { $0.isDefault }) {
            selectedDeviceIndex = i
        }
    }

    var selectedDevice: AudioInputDevice? {
        guard !devices.isEmpty,
              selectedDeviceIndex >= 0,
              selectedDeviceIndex < devices.count else { return nil }
        return devices[selectedDeviceIndex]
    }

    var elapsedFormatted: String {
        guard let st = startTime else { return "00:00:00" }
        let s = Int(Date().timeIntervalSince(st))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private static func defaultOutputDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings")
            .appendingPathComponent("recmeet")
    }
}

let appState = AppState()
#endif
