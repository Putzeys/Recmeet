import Foundation
import AVFoundation
import RecmeetCore

/// Helpers to convert `AVAudioPCMBuffer` (Float32 or Int16) into interleaved
/// 16-bit little-endian PCM bytes — the format consumed by `WAVChunkWriter`.
enum PCM {
    static func interleavedInt16LE(from buffer: AVAudioPCMBuffer) -> Data? {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0 else { return Data() }

        if let floatChannels = buffer.floatChannelData {
            var out = Data(count: frameCount * channelCount * 2)
            out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                let dst = raw.bindMemory(to: Int16.self).baseAddress!
                for f in 0..<frameCount {
                    for c in 0..<channelCount {
                        let s = max(-1.0, min(1.0, floatChannels[c][f]))
                        dst[f * channelCount + c] = Int16(s * 32767.0)
                    }
                }
            }
            return out
        }

        if let int16Channels = buffer.int16ChannelData {
            var out = Data(count: frameCount * channelCount * 2)
            out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                let dst = raw.bindMemory(to: Int16.self).baseAddress!
                for f in 0..<frameCount {
                    for c in 0..<channelCount {
                        dst[f * channelCount + c] = int16Channels[c][f]
                    }
                }
            }
            return out
        }
        return nil
    }
}
