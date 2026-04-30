#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

public final class MicRecorder {
    private let outputDir: URL
    private let preferredDevice: AudioInputDevice?
    private var capture: WASAPICapture?

    public let levelMonitor: MicLevelMonitor?

    /// Software gain — currently a no-op on Windows. Wire in v0.2.x once we
    /// add a Float32 intermediate in WASAPICapture.
    public var gain: Float = 1.0

    public var sampleRate: Double { Double(capture?.sampleRate ?? 48000) }
    public var channels: UInt32 { UInt32(capture?.channels ?? 1) }

    public init(outputDir: URL, device: AudioInputDevice?, gain: Float = 1.0, levelMonitor: MicLevelMonitor? = nil) {
        self.outputDir = outputDir
        self.preferredDevice = device
        self.gain = gain
        self.levelMonitor = levelMonitor
    }

    public func start() throws {
        Log.info("MicRecorder.start: opening input handle (id len=\(preferredDevice?.id.count ?? 0))")
        guard let dev = AudioDevices.openInputHandle(id: preferredDevice?.id) else {
            Log.error("MicRecorder.start: openInputHandle returned nil")
            throw COMError(hr: recmeet_E_FAIL, context: "No microphone device available")
        }
        Log.info("MicRecorder.start: opened device, building WASAPICapture")
        let capture = try WASAPICapture(
            device: dev,
            mode: .capture,
            outputDir: outputDir,
            filePrefix: "mic",
            levelMonitor: levelMonitor
        )
        Log.info("MicRecorder.start: WASAPICapture built, calling capture.start()")
        try capture.start()
        Log.info("MicRecorder.start: capture.start() OK")
        self.capture = capture
        Log.info("Mic recording at \(capture.sampleRate) Hz, \(capture.channels)ch (WASAPI)")
    }

    public func stop() {
        capture?.stop()
        capture = nil
    }
}

#endif
