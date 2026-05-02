#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

public enum WindowsAACEncoder {
    /// Transcode `inputWAV` to `outputM4A` at `bitrate` (default 128 kbps).
    /// Throws on Media Foundation failure.
    public static func encode(
        inputWAV: URL,
        outputM4A: URL,
        bitrate: UInt32 = 128_000
    ) throws {
        try? FileManager.default.removeItem(at: outputM4A)

        let hr = inputWAV.path.withCString(encodedAs: UTF16.self) { inPath in
            outputM4A.path.withCString(encodedAs: UTF16.self) { outPath in
                recmeet_encode_aac_from_wav(inPath, outPath, bitrate)
            }
        }
        if hr < 0 {
            throw COMError(hr: hr, context: "recmeet_encode_aac_from_wav")
        }
        Log.info("AAC encode → \(outputM4A.lastPathComponent)")
    }
}
#endif
