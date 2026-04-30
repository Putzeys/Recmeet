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
        do { try initializeCOM() } catch { return [] }

        guard let enumerator = makeDeviceEnumerator() else { return [] }
        defer { _ = enumerator.pointee.lpVtbl.pointee.Release(enumerator) }

        let defaultId = defaultCaptureDeviceId(enumerator)

        var collectionPtr: UnsafeMutablePointer<IMMDeviceCollection>?
        let hr = enumerator.pointee.lpVtbl.pointee.EnumAudioEndpoints(
            enumerator,
            eCapture,
            recmeet_DEVICE_STATE_ACTIVE,
            &collectionPtr
        )
        guard hr >= 0, let collection = collectionPtr else { return [] }
        defer { _ = collection.pointee.lpVtbl.pointee.Release(collection) }

        var count: UINT = 0
        _ = collection.pointee.lpVtbl.pointee.GetCount(collection, &count)

        var result: [AudioInputDevice] = []
        for i in 0..<count {
            var devPtr: UnsafeMutablePointer<IMMDevice>?
            guard collection.pointee.lpVtbl.pointee.Item(collection, i, &devPtr) >= 0,
                  let dev = devPtr else { continue }
            defer { _ = dev.pointee.lpVtbl.pointee.Release(dev) }

            var idPtr: LPWSTR?
            _ = dev.pointee.lpVtbl.pointee.GetId(dev, &idPtr)
            let id = stringFromWide(idPtr)
            coFreeWide(idPtr)

            let name = friendlyName(dev) ?? "<unknown>"
            let channels = inputChannelCount(dev)

            result.append(AudioInputDevice(
                id: id,
                name: name,
                inputChannels: channels,
                isDefault: id == defaultId
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

    public static func openDevice(id: String?) -> UnsafeMutablePointer<IMMDevice>? {
        do { try initializeCOM() } catch { return nil }
        guard let enumerator = makeDeviceEnumerator() else { return nil }
        defer { _ = enumerator.pointee.lpVtbl.pointee.Release(enumerator) }

        if let id {
            return id.withCString(encodedAs: UTF16.self) { wid -> UnsafeMutablePointer<IMMDevice>? in
                var devPtr: UnsafeMutablePointer<IMMDevice>?
                let hr = enumerator.pointee.lpVtbl.pointee.GetDevice(enumerator, wid, &devPtr)
                return hr >= 0 ? devPtr : nil
            }
        }

        var devPtr: UnsafeMutablePointer<IMMDevice>?
        _ = enumerator.pointee.lpVtbl.pointee.GetDefaultAudioEndpoint(enumerator, eCapture, eConsole, &devPtr)
        return devPtr
    }

    public static func openDefaultRenderDevice() -> UnsafeMutablePointer<IMMDevice>? {
        do { try initializeCOM() } catch { return nil }
        guard let enumerator = makeDeviceEnumerator() else { return nil }
        defer { _ = enumerator.pointee.lpVtbl.pointee.Release(enumerator) }
        var devPtr: UnsafeMutablePointer<IMMDevice>?
        _ = enumerator.pointee.lpVtbl.pointee.GetDefaultAudioEndpoint(enumerator, eRender, eConsole, &devPtr)
        return devPtr
    }

    // MARK: - Internals

    private static func makeDeviceEnumerator() -> UnsafeMutablePointer<IMMDeviceEnumerator>? {
        var ptr: LPVOID?
        var clsid = CLSID_MMDeviceEnumerator
        var iid   = IID_IMMDeviceEnumerator
        let hr = CoCreateInstance(
            &clsid,
            nil,
            recmeet_CLSCTX_ALL,
            &iid,
            &ptr
        )
        guard hr >= 0, let raw = ptr else { return nil }
        return raw.assumingMemoryBound(to: IMMDeviceEnumerator.self)
    }

    private static func defaultCaptureDeviceId(_ enumerator: UnsafeMutablePointer<IMMDeviceEnumerator>) -> String {
        var devPtr: UnsafeMutablePointer<IMMDevice>?
        guard enumerator.pointee.lpVtbl.pointee.GetDefaultAudioEndpoint(enumerator, eCapture, eConsole, &devPtr) >= 0,
              let dev = devPtr else { return "" }
        defer { _ = dev.pointee.lpVtbl.pointee.Release(dev) }
        var idPtr: LPWSTR?
        _ = dev.pointee.lpVtbl.pointee.GetId(dev, &idPtr)
        let id = stringFromWide(idPtr)
        coFreeWide(idPtr)
        return id
    }

    private static func friendlyName(_ device: UnsafeMutablePointer<IMMDevice>) -> String? {
        var storePtr: UnsafeMutablePointer<IPropertyStore>?
        guard device.pointee.lpVtbl.pointee.OpenPropertyStore(device, recmeet_STGM_READ, &storePtr) >= 0,
              let store = storePtr else { return nil }
        defer { _ = store.pointee.lpVtbl.pointee.Release(store) }

        var key = recmeet_PKEY_Device_FriendlyName
        var prop = PROPVARIANT()
        recmeet_PropVariantInit(&prop)
        defer { PropVariantClear(&prop) }

        guard store.pointee.lpVtbl.pointee.GetValue(store, &key, &prop) >= 0 else { return nil }
        guard prop.vt == recmeet_VT_LPWSTR else { return nil }
        return stringFromWide(prop.pwszVal)
    }

    private static func inputChannelCount(_ device: UnsafeMutablePointer<IMMDevice>) -> UInt32 {
        var clientPtr: LPVOID?
        var iid = IID_IAudioClient
        guard device.pointee.lpVtbl.pointee.Activate(
                device, &iid, recmeet_CLSCTX_ALL,
                nil as UnsafeMutablePointer<PROPVARIANT>?,
                &clientPtr) >= 0,
              let raw = clientPtr else { return 0 }
        let client = raw.assumingMemoryBound(to: IAudioClient.self)
        defer { _ = client.pointee.lpVtbl.pointee.Release(client) }

        var fmt: UnsafeMutablePointer<WAVEFORMATEX>?
        guard client.pointee.lpVtbl.pointee.GetMixFormat(client, &fmt) >= 0, let fmt else { return 0 }
        defer { CoTaskMemFree(UnsafeMutableRawPointer(fmt)) }
        return UInt32(fmt.pointee.nChannels)
    }
}

#endif
