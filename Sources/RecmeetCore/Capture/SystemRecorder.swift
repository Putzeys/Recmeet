import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Captures system audio via ScreenCaptureKit. Video frames are minimized
/// (1×1, 1 fps) since SCStream requires a video stream but we only consume audio.
public final class SystemRecorder: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var writer: WAVChunkWriter?
    private let outputDir: URL
    public let sampleRate: Double = 48000
    public let channels: UInt32 = 2
    private let sampleQueue = DispatchQueue(label: "recmeet.scstream.audio")

    public init(outputDir: URL) {
        self.outputDir = outputDir
    }

    public func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "recmeet", code: 10, userInfo: [NSLocalizedDescriptionKey: "No display available for SCStream"])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = Int(channels)
        config.excludesCurrentProcessAudio = true
        // Minimize video: SCStream requires a video target even when we only want audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        // We must also request video output but can ignore the buffers; otherwise SCStream errors out on some macOS versions.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        let writer = try WAVChunkWriter(
            directory: outputDir,
            prefix: "system",
            sampleRate: sampleRate,
            channels: channels
        )
        self.writer = writer
        self.stream = stream

        try await stream.startCapture()
        Log.info("System audio recording at \(Int(sampleRate)) Hz stereo")
    }

    public func stop() async {
        if let stream {
            do { try await stream.stopCapture() } catch { Log.error("SCStream stop: \(error)") }
        }
        writer?.close()
        stream = nil
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let writer else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let data = Self.interleavedInt16LE(from: sampleBuffer, targetChannels: Int(channels)) else { return }
        writer.writeInt16(data)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.error("SCStream stopped: \(error.localizedDescription)")
    }

    // MARK: - CMSampleBuffer → Int16 interleaved

    private static func interleavedInt16LE(from sb: CMSampleBuffer, targetChannels: Int) -> Data? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)?.pointee else {
            return nil
        }
        let frameCount = Int(CMSampleBufferGetNumSamples(sb))
        guard frameCount > 0 else { return Data() }

        // Pull AudioBufferList
        var blockBuffer: CMBlockBuffer?
        var ablSize: Int = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: &ablSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, ablSize > 0 else { return nil }

        let ablPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ablPtr.deallocate() }
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: ablSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let abl = UnsafeMutableAudioBufferListPointer(ablPtr.assumingMemoryBound(to: AudioBufferList.self))
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let srcChannels = Int(asbd.mChannelsPerFrame)

        // Gather per-channel float pointers (or copy out interleaved)
        var floatChannels: [UnsafePointer<Float>] = []
        if isFloat && isNonInterleaved {
            for b in abl {
                guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { return nil }
                floatChannels.append(UnsafePointer(p))
            }
        } else if isFloat {
            // Interleaved float — single buffer
            guard let buf = abl.first, let base = buf.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            // We will index manually below
            return Self.convertInterleavedFloat(base, frameCount: frameCount, srcChannels: srcChannels, targetChannels: targetChannels)
        } else {
            // Already integer PCM — convert via generic path
            return Self.convertInterleavedInt(abl: abl, asbd: asbd, frameCount: frameCount, srcChannels: srcChannels, targetChannels: targetChannels)
        }

        // Non-interleaved float → interleaved Int16, channel-mapped
        var out = Data(count: frameCount * targetChannels * 2)
        out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let dst = raw.bindMemory(to: Int16.self).baseAddress!
            for f in 0..<frameCount {
                for c in 0..<targetChannels {
                    let srcCh = min(c, srcChannels - 1)
                    let s = max(-1.0, min(1.0, floatChannels[srcCh][f]))
                    dst[f * targetChannels + c] = Int16(s * 32767.0)
                }
            }
        }
        return out
    }

    private static func convertInterleavedFloat(_ base: UnsafePointer<Float>, frameCount: Int, srcChannels: Int, targetChannels: Int) -> Data {
        var out = Data(count: frameCount * targetChannels * 2)
        out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let dst = raw.bindMemory(to: Int16.self).baseAddress!
            for f in 0..<frameCount {
                for c in 0..<targetChannels {
                    let srcCh = min(c, srcChannels - 1)
                    let s = max(-1.0, min(1.0, base[f * srcChannels + srcCh]))
                    dst[f * targetChannels + c] = Int16(s * 32767.0)
                }
            }
        }
        return out
    }

    private static func convertInterleavedInt(abl: UnsafeMutableAudioBufferListPointer, asbd: AudioStreamBasicDescription, frameCount: Int, srcChannels: Int, targetChannels: Int) -> Data? {
        // Fast path: already 16-bit interleaved with matching channel count
        let bits = Int(asbd.mBitsPerChannel)
        let nonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        guard bits == 16, !nonInterleaved,
              let buf = abl.first, let base = buf.mData?.assumingMemoryBound(to: Int16.self) else {
            return nil
        }
        if srcChannels == targetChannels {
            return Data(bytes: base, count: frameCount * targetChannels * 2)
        }
        var out = Data(count: frameCount * targetChannels * 2)
        out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let dst = raw.bindMemory(to: Int16.self).baseAddress!
            for f in 0..<frameCount {
                for c in 0..<targetChannels {
                    let srcCh = min(c, srcChannels - 1)
                    dst[f * targetChannels + c] = base[f * srcChannels + srcCh]
                }
            }
        }
        return out
    }
}
