import Foundation

#if os(Windows)
import WinSDK
import RecmeetCore

// Mirror every RecmeetCore Log call into the Windows app log so we can see
// recorder-internal failures too (stderr is /dev/null under SUBSYSTEM:WINDOWS).
Log.sink = { msg in appLog("core: \(msg)") }

// MARK: - Common Controls registration

var icc = INITCOMMONCONTROLSEX()
icc.dwSize = DWORD(MemoryLayout<INITCOMMONCONTROLSEX>.size)
icc.dwICC = DWORD(ICC_BAR_CLASSES | ICC_STANDARD_CLASSES)
_ = InitCommonControlsEx(&icc)

let hInstance = GetModuleHandleW(nil)

// MARK: - Window class

let className = Array("RecmeetMainWindow".utf16) + [WCHAR(0)]
let windowTitle = Array("recmeet".utf16) + [WCHAR(0)]

// IDC_ARROW = MAKEINTRESOURCE(32512). Swift's importer can't bring
// MAKEINTRESOURCE through (function-like macro), so we recreate the value
// inline as a low-bit-pattern pointer.
let kIDC_ARROW: UnsafePointer<WCHAR>? = UnsafePointer(bitPattern: 32512)

className.withUnsafeBufferPointer { classNamePtr in
    var wcex = WNDCLASSEXW()
    wcex.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wcex.style = UINT(CS_HREDRAW | CS_VREDRAW)
    wcex.lpfnWndProc = windowProc
    wcex.hInstance = hInstance
    wcex.hCursor = LoadCursorW(nil, kIDC_ARROW)
    wcex.hbrBackground = HBRUSH(bitPattern: UInt(COLOR_BTNFACE) + 1)
    wcex.lpszClassName = classNamePtr.baseAddress

    if RegisterClassExW(&wcex) == 0 {
        FileHandle.standardError.write(Data("recmeet: RegisterClassExW failed\n".utf8))
        exit(1)
    }

    if !registerMergeWindowClass(hInstance) {
        FileHandle.standardError.write(Data("recmeet: failed to register merge dialog class\n".utf8))
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
        // Tray-only by default — the tray icon is enough surface for the
        // 90% case (start/stop). User opens the config window from the
        // tray menu when they need it.
        UpdateWindow(hwnd)
    }
}

// MARK: - Message loop

var msg = MSG()
// Swift on Windows imports BOOL as Bool, so we just check the truthy value.
// (We lose the -1 error sentinel, but that's only set on bad HWNDs we never use.)
while GetMessageW(&msg, nil, 0, 0) {
    TranslateMessage(&msg)
    DispatchMessageW(&msg)
}

#else
print("RecmeetWin32App is Windows-only. On macOS use RecmeetApp instead.")
#endif
