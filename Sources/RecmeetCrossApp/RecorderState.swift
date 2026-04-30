import Foundation
import SwiftCrossUI
import RecmeetCore

#if os(macOS)
import RecmeetCoreApple
#elseif os(Windows)
import RecmeetCoreWindows
#endif

// `RecmeetCoreApple` transitively pulls Combine in via AVFoundation, which
// re-declares `ObservableObject` and `Published`. We pin everything in this
// file to SwiftCrossUI's versions explicitly to remove the ambiguity.
typealias _ObservableObject = SwiftCrossUI.ObservableObject
typealias _Published<T> = SwiftCrossUI.Published<T>

final class RecorderState: _ObservableObject {
    @_Published var devices: [AudioInputDevice] = []
    @_Published var selectedDeviceName: String? = nil
    @_Published var captureMic: Bool = true
    @_Published var captureSystem: Bool = true
    @_Published var gain: Double = 1.0
    @_Published var outputDir: URL = defaultOutputDir()

    @_Published var isRecording: Bool = false
    @_Published var elapsedSeconds: Int = 0
    @_Published var sessionPath: URL?
    @_Published var mergedFile: URL?
    @_Published var errorMessage: String?
    @_Published var isMixing: Bool = false

    private var mic: MicRecorder?
    private var system: SystemRecorder?
    private var startTime: Date?
    private var elapsedTimer: Timer?

    init() {
        refreshDevices()
    }

    var elapsedFormatted: String {
        let s = elapsedSeconds
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    func refreshDevices() {
        devices = AudioDevices.listInputs()
        if !devices.contains(where: { $0.name == selectedDeviceName }) {
            selectedDeviceName = devices.first(where: { $0.isDefault })?.name
                ?? devices.first?.name
        }
    }

    func toggle() async {
        if isRecording { await stop() } else { await start() }
    }

    func start() async {
        errorMessage = nil
        guard captureMic || captureSystem else {
            errorMessage = "Enable at least one source."
            return
        }

        #if os(macOS)
        if captureMic {
            guard await Permissions.requestMicrophone() else {
                errorMessage = "Microphone permission denied."
                Permissions.openMicrophoneSettings()
                return
            }
        }
        if captureSystem {
            guard await Permissions.ensureScreenRecording() else {
                errorMessage = "Screen Recording permission required."
                Permissions.openScreenRecordingSettings()
                return
            }
        }
        #endif

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let session = outputDir.appendingPathComponent(stamp)
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Cannot create folder: \(error.localizedDescription)"
            return
        }

        let chosen = devices.first(where: { $0.name == selectedDeviceName })

        do {
            if captureMic {
                let m = MicRecorder(outputDir: session, device: chosen, gain: Float(gain))
                try m.start()
                self.mic = m
            }
            if captureSystem {
                let s = SystemRecorder(outputDir: session)
                try await s.start()
                self.system = s
            }
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            mic?.stop()
            await system?.stop()
            mic = nil
            system = nil
            return
        }

        sessionPath = session
        mergedFile = nil
        startTime = Date()
        elapsedSeconds = 0
        isRecording = true

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let st = self.startTime else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(st))
        }
    }

    func stop() async {
        elapsedTimer?.invalidate()
        elapsedTimer = nil

        let hadMic = (mic != nil)
        let hadSystem = (system != nil)
        mic?.stop()
        await system?.stop()
        mic = nil
        system = nil
        isRecording = false

        guard let session = sessionPath, hadMic && hadSystem else { return }

        isMixing = true
        let opts = SessionMixer.Options(
            micVolume: 1.0,
            systemVolume: 1.0,
            keepSeparateTracks: false
        )
        do {
            let result = try await SessionMixer.merge(sessionDir: session, options: opts)
            mergedFile = result
        } catch {
            errorMessage = "Mix failed: \(error.localizedDescription)"
        }
        isMixing = false
    }

    private static func defaultOutputDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings")
            .appendingPathComponent("recmeet")
    }
}
