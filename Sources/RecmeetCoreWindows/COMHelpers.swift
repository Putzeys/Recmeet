#if os(Windows)
import WinSDK
import CWASAPI
import Foundation

public struct COMError: Error, CustomStringConvertible {
    public let hr: HRESULT
    public let context: String

    public init(hr: HRESULT, context: String) {
        self.hr = hr
        self.context = context
    }

    public var description: String {
        let raw = UInt32(bitPattern: Int32(hr))
        return "Windows audio error 0x\(String(format: "%08X", raw)) (\(context))"
    }
}

@inline(__always)
func checkHR(_ hr: HRESULT, _ context: @autoclosure () -> String) throws {
    if hr < 0 { throw COMError(hr: hr, context: context()) }
}

/// Convert a CoTaskMemAlloc'd wide string to Swift String and free it.
func consumeWide(_ ptr: LPWSTR?) -> String {
    guard let ptr else { return "" }
    var len = 0
    while ptr[len] != 0 { len += 1 }
    let buffer = UnsafeBufferPointer(start: ptr, count: len)
    let s = String(decoding: buffer, as: UTF16.self)
    CoTaskMemFree(UnsafeMutableRawPointer(ptr))
    return s
}

#endif
