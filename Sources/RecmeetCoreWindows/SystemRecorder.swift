#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

public final class SystemRecorder {
    private let outputDir: URL
    private var capture: WASAPICapture?
    private var keepalive: recmeet_keepalive_t?

    public init(outputDir: URL) {
        self.outputDir = outputDir
    }

    public func start() async throws {
        guard let dev = AudioDevices.openDefaultRenderHandle() else {
            throw COMError(hr: recmeet_E_FAIL, context: "No default render device for loopback")
        }

        // Render-side silent stream first, so by the time loopback begins
        // pulling, the engine is already pumping silence — no missed audio
        // when the user opens YouTube / joins a meeting AFTER pressing Record.
        if let kaDev = AudioDevices.openDefaultRenderHandle() {
            keepalive = recmeet_keepalive_start(kaDev)
            recmeet_device_release(kaDev)
            if keepalive != nil {
                Log.info("SystemRecorder: render keepalive started")
            } else {
                Log.error("SystemRecorder: render keepalive failed (continuing without it)")
            }
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
        if let k = keepalive {
            recmeet_keepalive_stop(k)
            keepalive = nil
            Log.info("SystemRecorder: render keepalive stopped")
        }
    }
}

#endif
