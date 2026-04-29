import Foundation

/// Thread-safe accumulator of the highest peak seen since the last drain.
/// MicRecorder feeds this from its capture thread; the UI polls `drainPeak()`
/// on a timer to drive a VU meter.
public final class MicLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0

    public init() {}

    /// Called from the audio capture thread.
    public func feed(_ value: Float) {
        lock.lock()
        if value > peak { peak = value }
        lock.unlock()
    }

    /// Returns the highest peak since the last drain and resets to 0.
    public func drainPeak() -> Float {
        lock.lock()
        let p = peak
        peak = 0
        lock.unlock()
        return p
    }
}
