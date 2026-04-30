#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

public struct AudioInputDevice: Hashable, Sendable {
    public let id: String
    public let name: String
    public let inputChannels: UInt32
    public let isDefault: Bool

    public var uid: String { id }
}

public enum AudioDevices {

    public static func listInputs() -> [AudioInputDevice] {
        _ = recmeet_init()

        let maxCount = 64
        let buffer = UnsafeMutablePointer<recmeet_device_t?>.allocate(capacity: maxCount)
        defer { buffer.deallocate() }

        let count = Int(recmeet_enumerate_capture_devices(buffer, Int32(maxCount)))
        var result: [AudioInputDevice] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            guard let dev = buffer[i] else { continue }
            defer { recmeet_device_release(dev) }

            let id   = consumeWide(recmeet_device_id(dev))
            let name = consumeWide(recmeet_device_name(dev))
            let ch   = recmeet_device_channel_count(dev)
            let isDefault = recmeet_device_is_default_capture(dev) != 0

            result.append(AudioInputDevice(
                id: id,
                name: name.isEmpty ? "<unknown>" : name,
                inputChannels: ch,
                isDefault: isDefault
            ))
        }
        return result
    }

    public static func find(byName name: String) -> AudioInputDevice? {
        let needle = name.lowercased()
        let all = listInputs()
        if let exact = all.first(where: { $0.name.lowercased() == needle }) { return exact }
        return all.first(where: { $0.name.lowercased().contains(needle) })
    }

    /// Caller owns the returned handle and must call recmeet_device_release.
    static func openInputHandle(id: String?) -> recmeet_device_t? {
        _ = recmeet_init()
        if let id, !id.isEmpty {
            return id.withCString(encodedAs: UTF16.self) { wid in
                recmeet_device_by_id(wid)
            }
        }
        return recmeet_default_capture_device()
    }

    /// Caller owns the returned handle and must call recmeet_device_release.
    static func openDefaultRenderHandle() -> recmeet_device_t? {
        _ = recmeet_init()
        return recmeet_default_render_device()
    }
}

#endif
