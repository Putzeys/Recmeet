#if os(Windows)
import WinSDK

// MARK: - Word/Param helpers (Windows macros that Swift can't import)

@inline(__always)
func LOWORD<T: BinaryInteger>(_ x: T) -> WORD {
    WORD(UInt(truncatingIfNeeded: x) & 0xFFFF)
}

@inline(__always)
func HIWORD<T: BinaryInteger>(_ x: T) -> WORD {
    WORD((UInt(truncatingIfNeeded: x) >> 16) & 0xFFFF)
}

@inline(__always)
func MAKELPARAM(_ lo: Int, _ hi: Int) -> LPARAM {
    LPARAM(Int32(truncatingIfNeeded: (UInt32(lo & 0xFFFF) | (UInt32(hi & 0xFFFF) << 16))))
}

// MARK: - String / pointer plumbing

extension String {
    /// Run `body` with this string materialised as a null-terminated UTF-16
    /// buffer. The buffer's lifetime ends with the closure.
    func withWide<R>(_ body: (UnsafePointer<WCHAR>) -> R) -> R {
        let utf16 = Array(self.utf16) + [WCHAR(0)]
        return utf16.withUnsafeBufferPointer { buf in
            body(buf.baseAddress!)
        }
    }
}

@inline(__always)
func ptrToLPARAM<T>(_ p: UnsafePointer<T>) -> LPARAM {
    LPARAM(Int(bitPattern: p))
}

func setControlText(_ hwnd: HWND?, _ text: String) {
    text.withWide { _ = SetWindowTextW(hwnd, $0) }
}
#endif
