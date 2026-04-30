#if os(Windows)
import WinSDK
import Foundation
import RecmeetCore

/// Minimal helpers for working with COM in Swift on Windows.
/// We deliberately keep this surface tiny — just enough to drive WASAPI.

public struct COMError: Error, LocalizedError {
    public let hr: HRESULT
    public let context: String

    public var errorDescription: String? {
        "COM error 0x\(String(format: "%08X", UInt32(bitPattern: Int32(hr)))) (\(context))"
    }
}

@inline(__always)
public func checkHR(_ hr: HRESULT, _ context: @autoclosure () -> String) throws {
    if hr < 0 {
        throw COMError(hr: hr, context: context())
    }
}

/// Initializes COM for the calling thread in MTA mode.
/// Safe to call once per thread; idempotent (`S_FALSE` is also success).
public func initializeCOM() throws {
    let hr = CoInitializeEx(nil, DWORD(COINIT_MULTITHREADED.rawValue))
    if hr < 0 { throw COMError(hr: hr, context: "CoInitializeEx") }
}

public func uninitializeCOM() {
    CoUninitialize()
}

/// Convert a Windows wide-string pointer (LPWSTR) to a Swift String.
public func stringFromWide(_ ptr: LPWSTR?) -> String {
    guard let ptr else { return "" }
    var len = 0
    while ptr[len] != 0 { len += 1 }
    let buffer = UnsafeBufferPointer(start: ptr, count: len)
    return String(decoding: buffer, as: UTF16.self)
}

public func stringFromWide(_ ptr: LPCWSTR?) -> String {
    guard let ptr else { return "" }
    var len = 0
    while ptr[len] != 0 { len += 1 }
    let buffer = UnsafeBufferPointer(start: ptr, count: len)
    return String(decoding: buffer, as: UTF16.self)
}

/// Frees a COM-allocated wide-string returned by APIs like `IMMDevice::GetId`.
public func coFreeWide(_ ptr: LPWSTR?) {
    if let ptr { CoTaskMemFree(UnsafeMutableRawPointer(ptr)) }
}

#endif
