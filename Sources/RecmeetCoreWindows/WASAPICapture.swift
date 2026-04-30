#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

final class WASAPICapture {
    enum Mode {
        case capture
        case loopback
    }

    private let device: UnsafeMutablePointer<IMMDevice>
    private let mode: Mode
    private let writer: WAVChunkWriter
    let sampleRate: UInt32
    let channels: UInt16

    private var client: UnsafeMutablePointer<IAudioClient>?
    private var capture: UnsafeMutablePointer<IAudioCaptureClient>?
    private var thread: Thread?
    private var stopFlag = false
    private let stopLock = NSLock()
    private let bytesPerFrame: Int
    private var levelMonitor: MicLevelMonitor?

    init(device: UnsafeMutablePointer<IMMDevice>,
         mode: Mode,
         outputDir: URL,
         filePrefix: String,
         levelMonitor: MicLevelMonitor? = nil) throws {
        self.device = device
        self.mode = mode
        self.levelMonitor = levelMonitor

        var clientRaw: LPVOID?
        var iid = IID_IAudioClient
        try checkHR(
            device.pointee.lpVtbl.pointee.Activate(
                device, &iid, recmeet_CLSCTX_ALL,
                nil as UnsafeMutablePointer<PROPVARIANT>?,
                &clientRaw
            ),
            "IMMDevice::Activate(IAudioClient)"
        )
        guard let raw = clientRaw else {
            throw COMError(hr: recmeet_E_FAIL, context: "Activate returned nil")
        }
        let client = raw.assumingMemoryBound(to: IAudioClient.self)
        self.client = client

        var mixFmtPtr: UnsafeMutablePointer<WAVEFORMATEX>?
        try checkHR(client.pointee.lpVtbl.pointee.GetMixFormat(client, &mixFmtPtr),
                    "IAudioClient::GetMixFormat")
        guard let mixFmtPtr else {
            throw COMError(hr: recmeet_E_FAIL, context: "GetMixFormat nil")
        }
        defer { CoTaskMemFree(UnsafeMutableRawPointer(mixFmtPtr)) }

        let nativeChannels = mixFmtPtr.pointee.nChannels
        let nativeRate = mixFmtPtr.pointee.nSamplesPerSec
        self.sampleRate = nativeRate
        self.channels = nativeChannels
        self.bytesPerFrame = Int(nativeChannels) * 2

        var fmt = WAVEFORMATEX()
        fmt.wFormatTag = WORD(WAVE_FORMAT_PCM)
        fmt.nChannels = nativeChannels
        fmt.nSamplesPerSec = nativeRate
        fmt.wBitsPerSample = 16
        fmt.nBlockAlign = nativeChannels * 2
        fmt.nAvgBytesPerSec = nativeRate * UInt32(fmt.nBlockAlign)
        fmt.cbSize = 0

        var streamFlags: DWORD = 0
        if mode == .loopback {
            streamFlags = recmeet_AUDCLNT_STREAMFLAGS_LOOPBACK
        }
        let bufferDuration: REFERENCE_TIME = 10_000_000

        try withUnsafePointer(to: &fmt) { fmtPtr in
            try checkHR(client.pointee.lpVtbl.pointee.Initialize(
                client,
                AUDCLNT_SHAREMODE_SHARED,
                streamFlags,
                bufferDuration,
                0,
                fmtPtr,
                nil as UnsafePointer<GUID>?
            ), "IAudioClient::Initialize")
        }

        var captureRaw: LPVOID?
        var capIid = IID_IAudioCaptureClient
        try checkHR(client.pointee.lpVtbl.pointee.GetService(client, &capIid, &captureRaw),
                    "IAudioClient::GetService(IAudioCaptureClient)")
        guard let capRaw = captureRaw else {
            throw COMError(hr: recmeet_E_FAIL, context: "capture nil")
        }
        self.capture = capRaw.assumingMemoryBound(to: IAudioCaptureClient.self)

        self.writer = try WAVChunkWriter(
            directory: outputDir,
            prefix: filePrefix,
            sampleRate: Double(nativeRate),
            channels: UInt32(nativeChannels)
        )
    }

    deinit {
        stop()
        if let capture { _ = capture.pointee.lpVtbl.pointee.Release(capture) }
        if let client { _ = client.pointee.lpVtbl.pointee.Release(client) }
        _ = device.pointee.lpVtbl.pointee.Release(device)
    }

    func start() throws {
        guard let client else {
            throw COMError(hr: recmeet_E_FAIL, context: "client released")
        }
        try checkHR(client.pointee.lpVtbl.pointee.Start(client), "IAudioClient::Start")
        let thread = Thread { [weak self] in self?.captureLoop() }
        thread.name = "recmeet.wasapi.capture"
        self.thread = thread
        thread.start()
    }

    func stop() {
        stopLock.lock(); stopFlag = true; stopLock.unlock()
        while let t = thread, t.isExecuting { Thread.sleep(forTimeInterval: 0.01) }
        thread = nil
        if let client { _ = client.pointee.lpVtbl.pointee.Stop(client) }
        writer.close()
    }

    private var shouldStop: Bool {
        stopLock.lock(); defer { stopLock.unlock() }
        return stopFlag
    }

    private func captureLoop() {
        guard let capture else { return }
        let bytesPerFrame = self.bytesPerFrame
        let levelMonitor = self.levelMonitor
        let writer = self.writer

        while !shouldStop {
            var packetSize: UINT32 = 0
            if capture.pointee.lpVtbl.pointee.GetNextPacketSize(capture, &packetSize) < 0 { break }
            if packetSize == 0 {
                Thread.sleep(forTimeInterval: 0.005)
                continue
            }

            var dataPtr: UnsafeMutablePointer<BYTE>?
            var numFrames: UINT32 = 0
            var flags: DWORD = 0
            let getHR = capture.pointee.lpVtbl.pointee.GetBuffer(
                capture, &dataPtr, &numFrames, &flags,
                nil as UnsafeMutablePointer<UINT64>?,
                nil as UnsafeMutablePointer<UINT64>?
            )
            if getHR < 0 { break }

            if let dataPtr, numFrames > 0 {
                let isSilent = (flags & recmeet_AUDCLNT_BUFFERFLAGS_SILENT) != 0
                let byteCount = Int(numFrames) * bytesPerFrame
                let chunk: Data
                if isSilent {
                    chunk = Data(count: byteCount)
                } else {
                    chunk = Data(bytes: UnsafeRawPointer(dataPtr), count: byteCount)
                }
                writer.writeInt16(chunk)

                if let levelMonitor {
                    levelMonitor.feed(Self.peakAmplitude(bytes: chunk))
                }
            }

            _ = capture.pointee.lpVtbl.pointee.ReleaseBuffer(capture, numFrames)
        }
    }

    private static func peakAmplitude(bytes: Data) -> Float {
        var maxAbs: Int16 = 0
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for s in samples {
                let abs = s == Int16.min ? Int16.max : Swift.abs(s)
                if abs > maxAbs { maxAbs = abs }
            }
        }
        return Float(maxAbs) / Float(Int16.max)
    }
}

#endif
