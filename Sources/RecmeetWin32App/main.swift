import Foundation

#if os(Windows)
import WinSDK

// MARK: - Common Controls registration

var icc = INITCOMMONCONTROLSEX()
icc.dwSize = DWORD(MemoryLayout<INITCOMMONCONTROLSEX>.size)
icc.dwICC = DWORD(ICC_BAR_CLASSES | ICC_STANDARD_CLASSES)
_ = InitCommonControlsEx(&icc)

let hInstance = GetModuleHandleW(nil)

// MARK: - Window class

let className = Array("RecmeetMainWindow".utf16) + [WCHAR(0)]
let windowTitle = Array("recmeet".utf16) + [WCHAR(0)]

className.withUnsafeBufferPointer { classNamePtr in
    var wcex = WNDCLASSEXW()
    wcex.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wcex.style = UINT(CS_HREDRAW | CS_VREDRAW)
    wcex.lpfnWndProc = windowProc
    wcex.hInstance = hInstance
    wcex.hCursor = LoadCursorW(nil, _IDC(IDC_ARROW))
    wcex.hbrBackground = HBRUSH(bitPattern: UInt(COLOR_BTNFACE) + 1)
    wcex.lpszClassName = classNamePtr.baseAddress

    if RegisterClassExW(&wcex) == 0 {
        FileHandle.standardError.write(Data("recmeet: RegisterClassExW failed\n".utf8))
        exit(1)
    }

    windowTitle.withUnsafeBufferPointer { titlePtr in
        let hwnd = CreateWindowExW(
            0,
            classNamePtr.baseAddress,
            titlePtr.baseAddress,
            DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX),
            CW_USEDEFAULT, CW_USEDEFAULT,
            480, 400,
            nil, nil, hInstance, nil
        )
        guard hwnd != nil else {
            FileHandle.standardError.write(Data("recmeet: CreateWindowExW failed\n".utf8))
            exit(1)
        }
        ShowWindow(hwnd, SW_SHOWNORMAL)
        UpdateWindow(hwnd)
    }
}

// MARK: - Message loop

var msg = MSG()
while GetMessageW(&msg, nil, 0, 0) > 0 {
    TranslateMessage(&msg)
    DispatchMessageW(&msg)
}

#else
import Foundation
print("RecmeetWin32App is Windows-only. On macOS use RecmeetApp instead.")
#endif

// IDC_ARROW is `MAKEINTRESOURCEW(32512)` — a function-style macro Swift can't
// import. We re-create it as a small Swift helper.
#if os(Windows)
@inline(__always)
private func _IDC(_ id: Int32) -> LPCWSTR {
    return UnsafePointer(bitPattern: Int(id))!
}
#endif
