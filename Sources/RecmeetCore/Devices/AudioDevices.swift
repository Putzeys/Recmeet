import Foundation
import CoreAudio

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let inputChannels: UInt32
    public let isDefault: Bool

    public init(id: AudioDeviceID, name: String, uid: String, inputChannels: UInt32, isDefault: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.inputChannels = inputChannels
        self.isDefault = isDefault
    }
}

public enum AudioDevices {
    public static func listInputs() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        return allDevices().compactMap { id in
            let inputs = inputChannelCount(deviceID: id)
            guard inputs > 0 else { return nil }
            return AudioInputDevice(
                id: id,
                name: stringProp(id, kAudioObjectPropertyName) ?? "<unknown>",
                uid: stringProp(id, kAudioDevicePropertyDeviceUID) ?? "",
                inputChannels: inputs,
                isDefault: id == defaultID
            )
        }
    }

    public static func find(byName name: String) -> AudioInputDevice? {
        let needle = name.lowercased()
        let all = listInputs()
        if let exact = all.first(where: { $0.name.lowercased() == needle }) { return exact }
        return all.first(where: { $0.name.lowercased().contains(needle) })
    }

    // MARK: - Core Audio HAL plumbing

    private static func allDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { buf -> OSStatus in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, buf.baseAddress!)
        }
        return status == noErr ? ids : []
    }

    private static func defaultInputDeviceID() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func inputChannelCount(deviceID: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let bufList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, bufList) == noErr else { return 0 }
        let abl = bufList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        var total: UInt32 = 0
        for b in buffers { total &+= b.mNumberChannels }
        return total
    }

    private static func stringProp(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cfStr) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        return status == noErr ? (cfStr as String) : nil
    }
}
