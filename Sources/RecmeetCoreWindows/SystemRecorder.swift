#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

/// System-audio capture for Windows. Uses the default render endpoint with
/// `AUDCLNT_STREAMFLAGS_LOOPBACK` — Windows' built-in loopback. No virtual
/// audio drivers required.
public final class SystemRecorder {
    private let outputDir: URL
    private var capture: WASAPICapture?

    public init(outputDir: URL) {
        self.outputDir = outputDir
    }

    public func start() async throws {
        guard let dev = AudioDevices.openDefaultRenderDevice() else {
            throw COMError(hr: recmeet_E_FAIL, context: "No default render device for loopback")
        }
        let capture = try WASAPICapture(
            device: dev,
            mode: .loopback,
            outputDir: outputDir,
            filePrefix: "system"
        )
        try capture.start()
        self.capture = capture
        Log.info("System audio recording at \(capture.sampleRate) Hz, \(capture.channels)ch (WASAPI loopback)")
    }

    public func stop() async {
        capture?.stop()
        capture = nil
    }
}

#endif
