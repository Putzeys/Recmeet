import Foundation

/// Streams mic + system chunk WAVs into a single mixed stereo WAV with
/// independent volume per source. Foundation-only — portable to Windows.
/// Memory bounded — safe for hours-long recordings.
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
        public var errorDescription: String? {
            switch self {
            case .noTracks: return "No mic or system chunks were found in the session."
            }
        }
    }

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

        let micReader = micURLs.isEmpty ? nil : try WAVChunkReader(urls: micURLs)
        let sysReader = sysURLs.isEmpty ? nil : try WAVChunkReader(urls: sysURLs)

        let totalFrames = max(
            (try? micReader?.totalFrames()) ?? 0,
            (try? sysReader?.totalFrames()) ?? 0
        )

        let bufFrames = 8192
        var micBuf: [Int16] = []
        var sysBuf: [Int16] = []
        var processed: Int64 = 0
        var lastReportedPct: Double = -1

        let micChannels = Int(micReader?.header.channels ?? 1)
        let sysChannels = Int(sysReader?.header.channels ?? 2)

        while true {
            let micRead = try micReader?.read(frameCount: bufFrames, into: &micBuf) ?? 0
            let sysRead = try sysReader?.read(frameCount: bufFrames, into: &sysBuf) ?? 0
            let frames = max(micRead, sysRead)
            if frames == 0 { break }

            let outData = mixToInt16Stereo(
                frames: frames,
                mic: micBuf, micFrames: micRead, micChannels: micChannels, micVolume: options.micVolume,
                sys: sysBuf, sysFrames: sysRead, sysChannels: sysChannels, sysVolume: options.systemVolume
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
        micReader?.close()
        sysReader?.close()

        if !options.keepSeparateTracks {
            for u in micURLs + sysURLs {
                try? FileManager.default.removeItem(at: u)
            }
        }
        return outURL
    }

    private static func mixToInt16Stereo(
        frames: Int,
        mic: [Int16], micFrames: Int, micChannels: Int, micVolume: Float,
        sys: [Int16], sysFrames: Int, sysChannels: Int, sysVolume: Float
    ) -> Data {
        let scale: Float = 1.0 / 32768.0
        var data = Data(count: frames * 2 * 2)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let dst = raw.bindMemory(to: Int16.self).baseAddress!
            for f in 0..<frames {
                var l: Float = 0
                var r: Float = 0
                if f < micFrames {
                    let m = Float(mic[f * micChannels]) * scale
                    let v = m * micVolume
                    l += v; r += v
                }
                if f < sysFrames {
                    let sL = Float(sys[f * sysChannels]) * scale
                    let sR = sysChannels >= 2 ? Float(sys[f * sysChannels + 1]) * scale : sL
                    l += sL * sysVolume
                    r += sR * sysVolume
                }
                l = max(-1, min(1, l))
                r = max(-1, min(1, r))
                dst[f * 2]     = Int16(l * 32767)
                dst[f * 2 + 1] = Int16(r * 32767)
            }
        }
        return data
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

/// Single-file 16-bit PCM WAV writer (Foundation only).
final class SingleWAVWriter {
    private let url: URL
    private let handle: FileHandle
    private var dataBytes: UInt32 = 0

    init(url: URL, sampleRate: UInt32, channels: UInt16) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
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
