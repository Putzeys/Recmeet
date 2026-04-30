#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

/// Drives one WASAPI capture session (mic OR system loopback) and writes the
/// PCM stream into a chunked WAV. All COM lives behind the C shim — Swift only
/// touches opaque handles.
final class WASAPICapture {
    enum Mode { case capture, loopback }

    private let device: recmeet_device_t
    private let cap: recmeet_capture_t
    private let writer: WAVChunkWriter
    let sampleRate: UInt32
    let channels: UInt16

    private let levelMonitor: MicLevelMonitor?
    private let bytesPerFrame: Int

    private var thread: Thread?
    private let stopLock = NSLock()
    private var stopFlag = false

    /// Takes ownership of `device` — releases it on deinit.
    init(device: recmeet_device_t,
         mode: Mode,
         outputDir: URL,
         filePrefix: String,
         levelMonitor: MicLevelMonitor? = nil) throws {
        self.device = device
        self.levelMonitor = levelMonitor

        var hr: HRESULT = 0
        let loopback: Int32 = (mode == .loopback) ? 1 : 0
        Log.info("WASAPICapture: recmeet_capture_create begin (loopback=\(loopback))")
        guard let cap = recmeet_capture_create(device, loopback, &hr) else {
            let hex = String(format: "0x%08X", UInt32(bitPattern: Int32(hr)))
            Log.error("WASAPICapture: recmeet_capture_create returned NULL hr=\(hex)")
            throw COMError(hr: hr, context: "recmeet_capture_create")
        }
        Log.info("WASAPICapture: recmeet_capture_create OK")
        self.cap = cap

        let format = recmeet_capture_format(cap)
        self.sampleRate = format.sample_rate
        self.channels = format.channels
        self.bytesPerFrame = Int(format.channels) * 2
        Log.info("WASAPICapture: format sr=\(format.sample_rate) ch=\(format.channels)")

        Log.info("WASAPICapture: opening WAVChunkWriter dir=\(outputDir.path) prefix=\(filePrefix)")
        do {
            self.writer = try WAVChunkWriter(
                directory: outputDir,
                prefix: filePrefix,
                sampleRate: Double(format.sample_rate),
                channels: UInt32(format.channels)
            )
            Log.info("WASAPICapture: WAVChunkWriter ready")
        } catch {
            Log.error("WASAPICapture: WAVChunkWriter failed — \(error.localizedDescription)")
            recmeet_capture_release(cap)
            throw error
        }
    }

    deinit {
        stop()
        recmeet_capture_release(cap)
        recmeet_device_release(device)
    }

    func start() throws {
        try checkHR(recmeet_capture_start(cap), "recmeet_capture_start")
        let t = Thread { [weak self] in self?.captureLoop() }
        t.name = "recmeet.wasapi.capture"
        self.thread = t
        t.start()
    }

    func stop() {
        stopLock.lock(); stopFlag = true; stopLock.unlock()
        while let t = thread, t.isExecuting { Thread.sleep(forTimeInterval: 0.01) }
        thread = nil
        _ = recmeet_capture_stop(cap)
        writer.close()
    }

    private var shouldStop: Bool {
        stopLock.lock(); defer { stopLock.unlock() }
        return stopFlag
    }

    private func captureLoop() {
        let bytesPerFrame = self.bytesPerFrame
        let monitor = self.levelMonitor

        while !shouldStop {
            var dataPtr: UnsafeMutableRawPointer?
            var frames: UInt32 = 0
            var flags: UInt32 = 0
            let ret = recmeet_capture_get_packet(cap, &dataPtr, &frames, &flags)
            if ret < 0 { break }
            if ret == 0 || frames == 0 {
                Thread.sleep(forTimeInterval: 0.005)
                continue
            }

            if let dataPtr {
                let isSilent = (flags & recmeet_AUDCLNT_BUFFERFLAGS_SILENT) != 0
                let byteCount = Int(frames) * bytesPerFrame
                let chunk: Data = isSilent
                    ? Data(count: byteCount)
                    : Data(bytes: UnsafeRawPointer(dataPtr), count: byteCount)

                writer.writeInt16(chunk)
                if let monitor { monitor.feed(Self.peakAmplitude(bytes: chunk)) }
            }
            recmeet_capture_release_packet(cap, frames)
        }
    }

    private static func peakAmplitude(bytes: Data) -> Float {
        var maxAbs: Int16 = 0
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for s in samples {
                let a = (s == Int16.min) ? Int16.max : Swift.abs(s)
                if a > maxAbs { maxAbs = a }
            }
        }
        return Float(maxAbs) / Float(Int16.max)
    }
}

#endif
