import Foundation

/// Writes interleaved 16-bit PCM into a sequence of WAV files.
/// Rotates to a new file when `secondsPerChunk` is reached so we never hit
/// the 4 GB WAV size limit and so a crash leaves valid chunks on disk.
public final class WAVChunkWriter {
    private let directory: URL
    private let prefix: String
    private let sampleRate: Double
    private let channels: UInt32
    private let secondsPerChunk: Double

    private var currentHandle: FileHandle?
    private var currentURL: URL?
    private var currentDataBytes: UInt32 = 0
    private var currentDurationSec: Double = 0
    private var chunkIndex = 0

    private let queue = DispatchQueue(label: "recmeet.wavwriter")

    public init(directory: URL, prefix: String, sampleRate: Double, channels: UInt32, secondsPerChunk: Double = 1800) throws {
        self.directory = directory
        self.prefix = prefix
        self.sampleRate = sampleRate
        self.channels = channels
        self.secondsPerChunk = secondsPerChunk
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try openNewChunk()
    }

    /// Append interleaved Int16 samples.
    public func writeInt16(_ data: Data) {
        queue.sync {
            do {
                if currentHandle == nil { try openNewChunk() }
                try currentHandle?.write(contentsOf: data)
                currentDataBytes &+= UInt32(data.count)
                let frames = Double(data.count) / Double(channels * 2)
                currentDurationSec += frames / sampleRate
                if currentDurationSec >= secondsPerChunk {
                    try rotate()
                }
            } catch {
                Log.error("WAV write failed: \(error)")
            }
        }
    }

    public func close() {
        queue.sync {
            do { try finalizeCurrent() } catch { Log.error("WAV finalize failed: \(error)") }
        }
    }

    // MARK: - Private

    private func openNewChunk() throws {
        let name = String(format: "%@_%03d.wav", prefix, chunkIndex)
        let url = directory.appendingPathComponent(name)
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        let header = Self.makeWAVHeader(dataSize: 0, sampleRate: UInt32(sampleRate), channels: UInt16(channels), bitsPerSample: 16)
        try handle.write(contentsOf: header)
        currentHandle = handle
        currentURL = url
        currentDataBytes = 0
        currentDurationSec = 0
    }

    private func rotate() throws {
        try finalizeCurrent()
        chunkIndex += 1
        try openNewChunk()
    }

    private func finalizeCurrent() throws {
        guard let handle = currentHandle, let url = currentURL else { return }
        try handle.close()

        // Patch WAV header sizes now that we know the data length.
        let fh = try FileHandle(forUpdating: url)
        let riffSize = UInt32(36) &+ currentDataBytes
        try fh.seek(toOffset: 4)
        try fh.write(contentsOf: withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
        try fh.seek(toOffset: 40)
        try fh.write(contentsOf: withUnsafeBytes(of: currentDataBytes.littleEndian) { Data($0) })
        try fh.close()

        currentHandle = nil
        currentURL = nil
    }

    public static func makeWAVHeader(dataSize: UInt32, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        var d = Data()
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        d.append("RIFF".data(using: .ascii)!)
        d.append(withUnsafeBytes(of: (UInt32(36) &+ dataSize).littleEndian) { Data($0) })
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        d.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })           // fmt chunk size
        d.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })            // PCM
        d.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        d.append("data".data(using: .ascii)!)
        d.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        return d
    }
}

