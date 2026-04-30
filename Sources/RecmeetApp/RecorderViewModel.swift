import Foundation
import AppKit
import Combine
import CoreAudio
import RecmeetCore
import RecmeetCoreApple

@MainActor
final class RecorderViewModel: ObservableObject {
    // Configuration
    @Published var devices: [AudioInputDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published var captureMic: Bool = true {
        didSet { UserDefaults.standard.set(captureMic, forKey: "captureMic") }
    }
    @Published var captureSystem: Bool = true {
        didSet { UserDefaults.standard.set(captureSystem, forKey: "captureSystem") }
    }
    @Published var gain: Float {
        didSet {
            mic?.gain = gain
            UserDefaults.standard.set(gain, forKey: "gain")
        }
    }
    @Published var outputDir: URL {
        didSet { UserDefaults.standard.set(outputDir.path, forKey: "outputDir") }
    }

    // Merge configuration
    @Published var micMergeVolume: Float {
        didSet { UserDefaults.standard.set(micMergeVolume, forKey: "micMergeVolume") }
    }
    @Published var systemMergeVolume: Float {
        didSet { UserDefaults.standard.set(systemMergeVolume, forKey: "systemMergeVolume") }
    }
    @Published var keepSeparateTracks: Bool {
        didSet { UserDefaults.standard.set(keepSeparateTracks, forKey: "keepSeparateTracks") }
    }
    @Published var alwaysAutoMerge: Bool {
        didSet { UserDefaults.standard.set(alwaysAutoMerge, forKey: "alwaysAutoMerge") }
    }

    // Live state
    @Published var isRecording: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var micLevel: Float = 0
    @Published var sessionPath: URL?
    @Published var mergedFile: URL?
    @Published var errorMessage: String?

    // Merge sheet state
    @Published var showMergeSheet: Bool = false
    @Published var isMixing: Bool = false
    @Published var mixingProgress: Double = 0

    // Internals
    private var mic: MicRecorder?
    private var system: SystemRecorder?
    private var levelMonitor: MicLevelMonitor?
    private var startTime: Date?
    private var timers: [Timer] = []

    init() {
        let defaults = UserDefaults.standard

        if let savedPath = defaults.string(forKey: "outputDir"), !savedPath.isEmpty {
            self.outputDir = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.outputDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Recordings/recmeet")
        }
        self.gain = (defaults.object(forKey: "gain") as? Float) ?? 1.0
        self.micMergeVolume = (defaults.object(forKey: "micMergeVolume") as? Float) ?? 1.0
        self.systemMergeVolume = (defaults.object(forKey: "systemMergeVolume") as? Float) ?? 1.0
        self.keepSeparateTracks = defaults.object(forKey: "keepSeparateTracks") as? Bool ?? false
        self.alwaysAutoMerge = defaults.object(forKey: "alwaysAutoMerge") as? Bool ?? false
        if defaults.object(forKey: "captureMic") != nil {
            self.captureMic = defaults.bool(forKey: "captureMic")
        }
        if defaults.object(forKey: "captureSystem") != nil {
            self.captureSystem = defaults.bool(forKey: "captureSystem")
        }
    }

    var elapsedFormatted: String {
        let s = elapsedSeconds
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    func refreshDevices() {
        devices = AudioDevices.listInputs()
        if !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first(where: { $0.isDefault })?.id ?? devices.first?.id ?? 0
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputDir
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url
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

        if captureMic {
            let granted = await Permissions.requestMicrophone()
            if !granted {
                Permissions.openMicrophoneSettings()
                errorMessage = "Microphone permission needed. Opened System Settings → Privacy & Security → Microphone — enable recmeet there, then click Record again."
                return
            }
        }
        if captureSystem {
            let granted = await Permissions.ensureScreenRecording()
            if !granted {
                Permissions.openScreenRecordingSettings()
                errorMessage = "Screen Recording permission needed. Opened System Settings → Privacy & Security → Screen Recording — enable recmeet there, then click Record again."
                return
            }
        }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let session = outputDir.appendingPathComponent(stamp)
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Cannot create folder: \(error.localizedDescription)"
            return
        }

        do {
            if captureMic {
                let dev = devices.first(where: { $0.id == selectedDeviceID })
                let monitor = MicLevelMonitor()
                self.levelMonitor = monitor
                let m = MicRecorder(outputDir: session, device: dev, gain: gain, levelMonitor: monitor)
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
            mic = nil; system = nil; levelMonitor = nil
            return
        }

        sessionPath = session
        startTime = Date()
        elapsedSeconds = 0
        isRecording = true
        scheduleTimers()
    }

    func stop() async {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        let hadMic = (mic != nil)
        let hadSystem = (system != nil)
        mic?.stop()
        await system?.stop()
        mic = nil
        system = nil
        levelMonitor = nil
        isRecording = false
        micLevel = 0
        mergedFile = nil

        guard hadMic && hadSystem else {
            // Only one source — nothing to merge.
            return
        }
        if alwaysAutoMerge {
            await runMerge()
        } else {
            showMergeSheet = true
        }
    }

    func runMerge() async {
        guard let session = sessionPath else { return }
        isMixing = true
        mixingProgress = 0
        errorMessage = nil

        let opts = SessionMixer.Options(
            micVolume: micMergeVolume,
            systemVolume: systemMergeVolume,
            keepSeparateTracks: keepSeparateTracks
        )
        do {
            let result = try await SessionMixer.merge(sessionDir: session, options: opts) { p in
                Task { @MainActor in self.mixingProgress = p }
            }
            mergedFile = result
            showMergeSheet = false
        } catch {
            errorMessage = "Mix failed: \(error.localizedDescription)"
        }
        isMixing = false
    }

    func skipMerge() {
        showMergeSheet = false
    }

    func revealSession() {
        let target = mergedFile ?? sessionPath
        guard let path = target else { return }
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    private func scheduleTimers() {
        let elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let st = self.startTime else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(st))
            }
        }
        let levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let p = self.levelMonitor?.drainPeak() ?? 0
                self.micLevel = max(p, self.micLevel * 0.85)
            }
        }
        timers = [elapsedTimer, levelTimer]
    }
}
