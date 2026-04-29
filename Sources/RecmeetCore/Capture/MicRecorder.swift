import Foundation
import AVFoundation
import CoreAudio

/// Captures the system input device (or a chosen one) via AVAudioEngine and
/// streams interleaved 16-bit PCM into a WAVChunkWriter at the device's native
/// sample rate, downmixed to mono.
public final class MicRecorder {
    private let engine = AVAudioEngine()
    private var writer: WAVChunkWriter?
    private let outputDir: URL
    private let preferredDevice: AudioInputDevice?

    public private(set) var sampleRate: Double = 48000
    public private(set) var channels: UInt32 = 1

    /// Linear gain multiplier applied before Int16 conversion. 1.0 = no change.
    /// Thread-safe to update while recording.
    private let gainLock = NSLock()
    private var _gain: Float = 1.0
    public var gain: Float {
        get { gainLock.lock(); defer { gainLock.unlock() }; return _gain }
        set { gainLock.lock(); _gain = max(0, newValue); gainLock.unlock() }
    }

    public let levelMonitor: MicLevelMonitor?

    public init(outputDir: URL, device: AudioInputDevice?, gain: Float = 1.0, levelMonitor: MicLevelMonitor? = nil) {
        self.outputDir = outputDir
        self.preferredDevice = device
        self._gain = max(0, gain)
        self.levelMonitor = levelMonitor
    }

    public func start() throws {
        if let dev = preferredDevice {
            try setInputDevice(dev.id)
            Log.info("Mic device: \(dev.name)")
        } else {
            Log.info("Mic device: system default")
        }

        let input = engine.inputNode
        let nativeFormat = input.inputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0 else {
            throw NSError(domain: "recmeet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mic input format unavailable"])
        }
        sampleRate = nativeFormat.sampleRate
        channels = 1

        let writer = try WAVChunkWriter(
            directory: outputDir,
            prefix: "mic",
            sampleRate: sampleRate,
            channels: channels
        )
        self.writer = writer

        let monitor = self.levelMonitor
        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let mono = Self.downmixToMono(buffer)
            let g = self.gain
            if g != 1.0 { Self.applyGain(mono, gain: g) }
            if let monitor { monitor.feed(Self.peak(mono)) }
            if let data = PCM.interleavedInt16LE(from: mono) {
                writer.writeInt16(data)
            }
        }

        try engine.start()
        Log.info(String(format: "Mic recording at %.0f Hz mono", sampleRate))
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer?.close()
    }

    private static func applyGain(_ buffer: AVAudioPCMBuffer, gain: Float) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        for c in 0..<channels {
            let p = data[c]
            for f in 0..<frames { p[f] *= gain }
        }
    }

    private static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var maxAbs: Float = 0
        for c in 0..<channels {
            let p = data[c]
            for f in 0..<frames {
                let a = abs(p[f])
                if a > maxAbs { maxAbs = a }
            }
        }
        return maxAbs
    }

    // MARK: - Helpers

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let unit = engine.inputNode.audioUnit else {
            throw NSError(domain: "recmeet", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio unit on input node"])
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw NSError(domain: "recmeet", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set input device (status \(status))"])
        }
    }

    private static func downmixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let inChannels = Int(buffer.format.channelCount)
        if inChannels == 1 { return buffer }
        guard let inData = buffer.floatChannelData else { return buffer }

        let frames = Int(buffer.frameLength)
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1)!
        guard let out = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames)) else { return buffer }
        out.frameLength = AVAudioFrameCount(frames)
        let dst = out.floatChannelData![0]
        let inv = 1.0 / Float(inChannels)
        for f in 0..<frames {
            var s: Float = 0
            for c in 0..<inChannels { s += inData[c][f] }
            dst[f] = s * inv
        }
        return out
    }
}
