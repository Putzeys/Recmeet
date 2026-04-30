#if os(Windows)
import WinSDK
import Foundation
import RecmeetCore

/// Microphone capture for Windows. Wraps `WASAPICapture` in `.capture` mode
/// against either the chosen `AudioInputDevice` or the system default.
public final class MicRecorder {
    private let outputDir: URL
    private let preferredDevice: AudioInputDevice?
    private var capture: WASAPICapture?

    public let levelMonitor: MicLevelMonitor?

    /// Software gain applied at the WASAPI layer. NOT yet implemented on Windows
    /// (stubbed to satisfy the cross-platform API; the capture path passes raw
    /// samples through). Wire in v0.2.x once we move to a Float32-intermediate
    /// pipeline.
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
        let dev = AudioDevices.openDevice(id: preferredDevice?.id)
        guard let dev else {
            throw COMError(hr: E_FAIL, context: "No microphone device available")
        }
        let capture = try WASAPICapture(
            device: dev,
            mode: .capture,
            outputDir: outputDir,
            filePrefix: "mic",
            levelMonitor: levelMonitor
        )
        try capture.start()
        self.capture = capture
        Log.info("Mic recording at \(capture.sampleRate) Hz, \(capture.channels)ch (WASAPI)")
    }

    public func stop() {
        capture?.stop()
        capture = nil
    }
}

#endif
