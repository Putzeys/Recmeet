import Foundation

/// Sequential reader across a list of 16-bit PCM WAV chunks.
/// Foundation-only — works on macOS, Windows, and Linux.
///
/// All chunks are assumed to share the same sample rate and channel count
/// (which is guaranteed by `WAVChunkWriter`).
public final class WAVChunkReader {
    public struct Chunk {
        public let url: URL
        public let header: WAVHeader
    }

    public let urls: [URL]
    public let header: WAVHeader

    private var fileIndex = 0
    private var currentHandle: FileHandle?
    private var currentBytesRemaining: Int64 = 0

    public init(urls: [URL]) throws {
        self.urls = urls
        guard let first = urls.first else {
            throw IOError.empty
        }
        // Header from the first chunk; assume the rest match.
        self.header = try WAVHeader.parse(url: first)
        try openChunk(at: 0)
    }

    /// Total number of frames across every chunk in the list.
    public func totalFrames() throws -> Int64 {
        var sum: Int64 = 0
        for url in urls {
            let h = try WAVHeader.parse(url: url)
            sum += Int64(h.dataSize) / Int64(h.bytesPerFrame)
        }
        return sum
    }

    /// Reads up to `frameCount` frames (across chunk boundaries) into `buffer`.
    /// Returns the actual number of frames read. 0 means EOF on every chunk.
    public func read(frameCount: Int, into buffer: inout [Int16]) throws -> Int {
        let bytesPerFrame = Int(header.bytesPerFrame)
        let wantedBytes = frameCount * bytesPerFrame
        if buffer.count < frameCount * Int(header.channels) {
            buffer = [Int16](repeating: 0, count: frameCount * Int(header.channels))
        }

        var producedFrames = 0
        var remainingBytes = wantedBytes

        while remainingBytes > 0 {
            if currentHandle == nil || currentBytesRemaining == 0 {
                fileIndex += 1
                if fileIndex >= urls.count { break }
                try openChunk(at: fileIndex)
            }
            guard let handle = currentHandle else { break }

            let take = Int(min(Int64(remainingBytes), currentBytesRemaining))
            guard take > 0 else { continue }

            guard let data = try handle.read(upToCount: take), !data.isEmpty else {
                // Truncated file — skip to next chunk.
                currentBytesRemaining = 0
                continue
            }
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let src = raw.bindMemory(to: Int16.self)
                let frameOffset = producedFrames * Int(header.channels)
                for i in 0..<src.count {
                    buffer[frameOffset + i] = Int16(littleEndian: src[i])
                }
            }
            let framesGot = data.count / bytesPerFrame
            producedFrames += framesGot
            currentBytesRemaining -= Int64(data.count)
            remainingBytes -= data.count
        }
        return producedFrames
    }

    public func close() {
        try? currentHandle?.close()
        currentHandle = nil
    }

    deinit { close() }

    private func openChunk(at index: Int) throws {
        try? currentHandle?.close()
        let url = urls[index]
        let h = try WAVHeader.parse(url: url)
        let handle = try FileHandle(forReadingFrom: url)
        try handle.seek(toOffset: h.dataOffset)
        currentHandle = handle
        currentBytesRemaining = Int64(h.dataSize)
    }
}

public struct WAVHeader: Sendable {
    public let sampleRate: UInt32
    public let channels: UInt16
    public let bitsPerSample: UInt16
    public let dataOffset: UInt64
    public let dataSize: UInt32

    public var bytesPerFrame: UInt32 {
        UInt32(channels) * UInt32(bitsPerSample / 8)
    }

    /// Parses a WAV file's header far enough to find the `data` chunk.
    /// Skips JUNK / LIST / fact / id3 / etc. chunks.
    public static func parse(url: URL) throws -> WAVHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let riff = try handle.read(upToCount: 12), riff.count == 12 else {
            throw IOError.malformedHeader("missing RIFF prologue")
        }
        guard riff.subdata(in: 0..<4) == Data("RIFF".utf8),
              riff.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            throw IOError.malformedHeader("not a WAVE file")
        }

        var sampleRate: UInt32 = 0
        var channels: UInt16 = 0
        var bits: UInt16 = 0

        while true {
            guard let head = try handle.read(upToCount: 8), head.count == 8 else {
                throw IOError.malformedHeader("missing chunk header")
            }
            let id = String(decoding: head.subdata(in: 0..<4), as: UTF8.self)
            let size = head.subdata(in: 4..<8).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
            switch id {
            case "fmt ":
                guard let fmt = try handle.read(upToCount: Int(size)), fmt.count == Int(size) else {
                    throw IOError.malformedHeader("truncated fmt")
                }
                channels = fmt.subdata(in: 2..<4).withUnsafeBytes {
                    $0.load(as: UInt16.self).littleEndian
                }
                sampleRate = fmt.subdata(in: 4..<8).withUnsafeBytes {
                    $0.load(as: UInt32.self).littleEndian
                }
                bits = fmt.subdata(in: 14..<16).withUnsafeBytes {
                    $0.load(as: UInt16.self).littleEndian
                }
            case "data":
                let offset = try handle.offset()
                return WAVHeader(
                    sampleRate: sampleRate,
                    channels: channels,
                    bitsPerSample: bits,
                    dataOffset: offset,
                    dataSize: size
                )
            default:
                // Skip unknown chunk.
                let here = try handle.offset()
                try handle.seek(toOffset: here + UInt64(size))
            }
        }
    }
}

public enum IOError: Error, LocalizedError {
    case empty
    case malformedHeader(String)

    public var errorDescription: String? {
        switch self {
        case .empty: return "No chunks supplied to reader."
        case .malformedHeader(let why): return "Malformed WAV header: \(why)"
        }
    }
}
