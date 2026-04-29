import Foundation
import AVFoundation

/// Streams mic and system chunk WAVs into a single mixed stereo WAV with
/// independent volume controls for each source. Memory usage is bounded —
/// safe for hours-long recordings.
public enum SessionMixer {

    public struct Options: Sendable {
        public var micVolume: Float        // 0..1
        public var systemVolume: Float     // 0..1
        public var keepSeparateTracks: Bool
        public var outputName: String

        public init(
            micVolume: Float = 1.0,
            systemVolume: Float = 1.0,
            keepSeparateTracks: Bool = false,
            outputName: String = "mixed.wav"
        ) {
            self.micVolume = micVolume
            self.systemVolume = systemVolume
            self.keepSeparateTracks = keepSeparateTracks
            self.outputName = outputName
        }
    }

    public enum MixError: Error, LocalizedError {
        case noTracks
        case unsupportedFormat(String)

        public var errorDescription: String? {
            switch self {
            case .noTracks: return "No mic or system chunks were found in the session."
            case .unsupportedFormat(let s): return "Unsupported chunk format: \(s)"
            }
        }
    }

    /// Merges chunks under `sessionDir` into a single `mixed.wav`.
    /// Returns the resulting file URL.
    public static func merge(
        sessionDir: URL,
        options: Options,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try mergeSync(sessionDir: sessionDir, options: options, progress: progress)
        }.value
    }

    // MARK: - Implementation

    private static func mergeSync(
        sessionDir: URL,
        options: Options,
        progress: (@Sendable (Double) -> Void)?
    ) throws -> URL {
        let micURLs = chunks(in: sessionDir, prefix: "mic")
        let sysURLs = chunks(in: sessionDir, prefix: "system")
        guard !micURLs.isEmpty || !sysURLs.isEmpty else { throw MixError.noTracks }

        let outURL = sessionDir.appendingPathComponent(options.outputName)
        let outWriter = try SingleWAVWriter(url: outURL, sampleRate: 48000, channels: 2)

        let micFiles = try micURLs.map { try AVAudioFile(forReading: $0) }
        let sysFiles = try sysURLs.map { try AVAudioFile(forReading: $0) }

        let micFormat = micFiles.first?.processingFormat
            ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let sysFormat = sysFiles.first?.processingFormat
            ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        let totalFrames = max(
            micFiles.reduce(Int64(0)) { $0 + $1.length },
            sysFiles.reduce(Int64(0)) { $0 + $1.length }
        )

        let bufFrames: AVAudioFrameCount = 8192
        var micFileIdx = 0
        var sysFileIdx = 0
        var processed: Int64 = 0
        var lastReportedPct: Double = -1

        while true {
            let micBuf = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: bufFrames)!
            let sysBuf = AVAudioPCMBuffer(pcmFormat: sysFormat, frameCapacity: bufFrames)!
            let micRead = readSequential(files: micFiles, currentIndex: &micFileIdx, into: micBuf, target: bufFrames)
            let sysRead = readSequential(files: sysFiles, currentIndex: &sysFileIdx, into: sysBuf, target: bufFrames)

            let frames = Int(max(micRead, sysRead))
            if frames == 0 { break }

            let outData = mixToInt16Stereo(
                frames: frames,
                mic: micBuf, micFrames: Int(micRead), micVolume: options.micVolume,
                sys: sysBuf, sysFrames: Int(sysRead), sysVolume: options.systemVolume
            )
            try outWriter.write(outData)

            processed += Int64(frames)
            if let progress, totalFrames > 0 {
                let pct = Double(processed) / Double(totalFrames)
                if pct - lastReportedPct >= 0.01 {
                    lastReportedPct = pct
                    progress(min(1, pct))
                }
            }
        }

        try outWriter.close()
        progress?(1.0)

        if !options.keepSeparateTracks {
            for u in micURLs + sysURLs {
                try? FileManager.default.removeItem(at: u)
            }
        }
        return outURL
    }

    private static func mixToInt16Stereo(
        frames: Int,
        mic: AVAudioPCMBuffer, micFrames: Int, micVolume: Float,
        sys: AVAudioPCMBuffer, sysFrames: Int, sysVolume: Float
    ) -> Data {
        let micData = mic.floatChannelData
        let sysData = sys.floatChannelData
        let sysHasStereo = sys.format.channelCount >= 2

        var data = Data(count: frames * 2 * 2) // frames * channels(2) * bytes(2)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let dst = raw.bindMemory(to: Int16.self).baseAddress!
            for f in 0..<frames {
                var l: Float = 0
                var r: Float = 0
                if f < micFrames, let mic = micData {
                    let v = mic[0][f] * micVolume
                    l += v; r += v
                }
                if f < sysFrames, let sys = sysData {
                    l += sys[0][f] * sysVolume
                    r += (sysHasStereo ? sys[1][f] : sys[0][f]) * sysVolume
                }
                l = max(-1, min(1, l))
                r = max(-1, min(1, r))
                dst[f * 2] = Int16(l * 32767)
                dst[f * 2 + 1] = Int16(r * 32767)
            }
        }
        return data
    }

    /// Reads up to `target` frames from a list of AVAudioFiles, stepping to
    /// the next file when one is exhausted. Fills the buffer's channels in
    /// order. Returns the actual number of frames written.
    private static func readSequential(
        files: [AVAudioFile],
        currentIndex: inout Int,
        into buf: AVAudioPCMBuffer,
        target: AVAudioFrameCount
    ) -> AVAudioFrameCount {
        var totalRead: AVAudioFrameCount = 0
        var remaining = target
        let channels = Int(buf.format.channelCount)

        while currentIndex < files.count && remaining > 0 {
            let file = files[currentIndex]
            let avail = AVAudioFrameCount(max(0, file.length - file.framePosition))
            if avail == 0 { currentIndex += 1; continue }

            let toRead = min(remaining, avail)
            guard let temp = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: toRead) else { break }
            do {
                try file.read(into: temp, frameCount: toRead)
            } catch {
                break
            }
            let actuallyRead = temp.frameLength
            if actuallyRead == 0 {
                currentIndex += 1
                continue
            }

            if let dst = buf.floatChannelData, let src = temp.floatChannelData {
                for c in 0..<channels {
                    let dstP = dst[c].advanced(by: Int(totalRead))
                    let srcP = src[c]
                    dstP.update(from: srcP, count: Int(actuallyRead))
                }
            }
            totalRead += actuallyRead
            remaining -= actuallyRead
            if file.framePosition >= file.length { currentIndex += 1 }
        }
        buf.frameLength = totalRead
        return totalRead
    }

    private static func chunks(in dir: URL, prefix: String) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix + "_") && $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Single-file 16-bit PCM WAV writer used by the mixer.
private final class SingleWAVWriter {
    private let url: URL
    private let handle: FileHandle
    private var dataBytes: UInt32 = 0
    private let sampleRate: UInt32
    private let channels: UInt16

    init(url: URL, sampleRate: UInt32, channels: UInt16) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
        self.sampleRate = sampleRate
        self.channels = channels
        let header = WAVChunkWriter.makeWAVHeader(
            dataSize: 0,
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: 16
        )
        try handle.write(contentsOf: header)
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        dataBytes &+= UInt32(data.count)
    }

    func close() throws {
        try handle.close()
        let fh = try FileHandle(forUpdating: url)
        let riffSize = UInt32(36) &+ dataBytes
        try fh.seek(toOffset: 4)
        try fh.write(contentsOf: withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
        try fh.seek(toOffset: 40)
        try fh.write(contentsOf: withUnsafeBytes(of: dataBytes.littleEndian) { Data($0) })
        try fh.close()
    }
}
