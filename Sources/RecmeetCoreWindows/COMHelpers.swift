#if os(Windows)
import WinSDK
import CWASAPI
import Foundation
import RecmeetCore

public struct COMError: Error, CustomStringConvertible {
    public let hr: HRESULT
    public let context: String

    public var description: String {
        let raw = UInt32(bitPattern: Int32(hr))
        return "COM error 0x\(String(format: "%08X", raw)) (\(context))"
    }
}

@inline(__always)
public func checkHR(_ hr: HRESULT, _ context: @autoclosure () -> String) throws {
    if hr < 0 {
        throw COMError(hr: hr, context: context())
    }
}

public func initializeCOM() throws {
    let hr = CoInitializeEx(nil, DWORD(COINIT_MULTITHREADED.rawValue))
    if hr < 0 { throw COMError(hr: hr, context: "CoInitializeEx") }
}

public func uninitializeCOM() {
    CoUninitialize()
}

public func stringFromWide(_ ptr: LPWSTR?) -> String {
    guard let ptr else { return "" }
    var len = 0
    while ptr[len] != 0 { len += 1 }
    let buffer = UnsafeBufferPointer(start: ptr, count: len)
    return String(decoding: buffer, as: UTF16.self)
}

public func coFreeWide(_ ptr: LPWSTR?) {
    if let ptr { CoTaskMemFree(UnsafeMutableRawPointer(ptr)) }
}

#endif
