import Foundation
import AVFoundation
import RecmeetCore

/// Transcodes a mono / stereo PCM WAV into an AAC-in-M4A file using
/// AVAssetWriter. We do this after `SessionMixer` has produced
/// `mixed.wav` so the user gets a small, transcription-ready artifact
/// (≈30 MB / hour vs ≈700 MB / hour for the raw WAV).
///
/// We use AVAssetWriter (not the simpler AVAssetExportSession) because
/// the export-session preset path renders `mixed.m4a` next to the source
/// only after the entire AVAsset pipeline spins up — that adds noticeable
/// latency on long sessions. AVAssetWriter streams sample buffers
/// directly and finishes in roughly real-time-of-source / 20.
public enum AppleAACEncoder {

    /// Encode `inputWAV` to `outputM4A` at `bitrate` (default 128 kbps).
    /// Throws on any AVFoundation failure.
    public static func encode(
        inputWAV: URL,
        outputM4A: URL,
        bitrate: Int = 128_000
    ) async throws {
        try? FileManager.default.removeItem(at: outputM4A)

        let reader = try AVAssetReader(asset: AVURLAsset(url: inputWAV))
        guard let track = try await AVURLAsset(url: inputWAV).loadTracks(withMediaType: .audio).first else {
            throw NSError(
                domain: "recmeet.aac",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Input WAV has no audio track."]
            )
        }
        let readerSettings: [String: Any] = [
            AVFormatIDKey:           kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey:  16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey:   false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        guard reader.canAdd(readerOutput) else {
            throw NSError(domain: "recmeet.aac", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Reader rejected output."])
        }
        reader.add(readerOutput)

        let formatDesc = try await track.load(.formatDescriptions).first
        var channels = 2
        var sampleRate: Double = 48000
        if let desc = formatDesc as! CMAudioFormatDescription? {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                channels = Int(asbd.mChannelsPerFrame)
                sampleRate = asbd.mSampleRate
            }
        }

        let writerSettings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey:       channels,
            AVSampleRateKey:             sampleRate,
            AVEncoderBitRateKey:         bitrate,
        ]
        let writer = try AVAssetWriter(outputURL: outputM4A, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "recmeet.aac", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Writer rejected AAC input."])
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "recmeet.aac", code: 4)
        }
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "recmeet.aac", code: 5)
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "recmeet.aac.encoder")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        if !writerInput.append(buffer) {
                            writerInput.markAsFinished()
                            cont.resume(throwing: writer.error ?? NSError(domain: "recmeet.aac", code: 6))
                            return
                        }
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                cont.resume()
                            } else {
                                cont.resume(throwing: writer.error
                                    ?? NSError(domain: "recmeet.aac", code: 7))
                            }
                        }
                        return
                    }
                }
            }
        }

        Log.info("AAC encode → \(outputM4A.lastPathComponent) (\(channels)ch, \(Int(sampleRate))Hz, \(bitrate/1000)kbps)")
    }
}
