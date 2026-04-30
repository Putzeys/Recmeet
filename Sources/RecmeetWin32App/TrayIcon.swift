#if os(Windows)
import WinSDK
import Foundation

let WM_TRAYICON: UINT = UINT(WM_USER) + 10

let ID_TRAY_RECORD:  WORD = 200
let ID_TRAY_SHOW:    WORD = 201
let ID_TRAY_REVEAL:  WORD = 202
let ID_TRAY_UPDATES: WORD = 203
let ID_TRAY_QUIT:    WORD = 204

private var nid = NOTIFYICONDATAW()
private var trayInstalled = false

/// Adds the recmeet icon to the Windows system tray. The tray's HWND is the
/// main window — clicks come back as `WM_TRAYICON` messages we route below.
func installTrayIcon(parent: HWND?) {
    guard let parent else { return }
    let hInst = GetModuleHandleW(nil)

    nid = NOTIFYICONDATAW()
    nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
    nid.hWnd = parent
    nid.uID = 1
    nid.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
    nid.uCallbackMessage = WM_TRAYICON

    // Resource ID 1 was declared in recmeet.rc — same icon as the .exe.
    nid.hIcon = LoadIconW(hInst, UnsafePointer<WCHAR>(bitPattern: 1))
    if nid.hIcon == nil {
        nid.hIcon = LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDI_APPLICATION
    }

    let tip = "recmeet"
    let utf16 = Array(tip.utf16) + [WCHAR(0)]
    withUnsafeMutableBytes(of: &nid.szTip) { buf in
        utf16.withUnsafeBufferPointer { src in
            let dst = buf.bindMemory(to: WCHAR.self)
            let copyCount = min(dst.count, src.count)
            for i in 0..<copyCount { dst[i] = src[i] }
        }
    }

    if Shell_NotifyIconW(DWORD(NIM_ADD), &nid) {
        trayInstalled = true
    }
}

func updateTrayTip(_ text: String) {
    guard trayInstalled else { return }
    nid.uFlags = UINT(NIF_TIP)
    let utf16 = Array(text.utf16) + [WCHAR(0)]
    withUnsafeMutableBytes(of: &nid.szTip) { buf in
        // Clear existing.
        for i in 0..<buf.count { buf[i] = 0 }
        utf16.withUnsafeBufferPointer { src in
            let dst = buf.bindMemory(to: WCHAR.self)
            let copyCount = min(dst.count, src.count)
            for i in 0..<copyCount { dst[i] = src[i] }
        }
    }
    _ = Shell_NotifyIconW(DWORD(NIM_MODIFY), &nid)
}

func removeTrayIcon() {
    guard trayInstalled else { return }
    _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &nid)
    trayInstalled = false
}

/// Build and pop up the right-click menu at the cursor position.
func showTrayPopupMenu(parent: HWND?) {
    guard let parent else { return }
    let menu = CreatePopupMenu()
    defer { DestroyMenu(menu) }

    let recordLabel = appState.isRecording ? "Stop Recording" : "Start Recording"
    recordLabel.withWide { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(ID_TRAY_RECORD), $0) }

    _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)

    "Show Window".withWide { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(ID_TRAY_SHOW), $0) }
    if appState.mergedFile != nil || appState.sessionPath != nil {
        "Reveal Last Recording".withWide { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(ID_TRAY_REVEAL), $0) }
    }

    _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)

    "Check for Updates…".withWide { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(ID_TRAY_UPDATES), $0) }

    _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)

    "Quit recmeet".withWide { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(ID_TRAY_QUIT), $0) }

    var pt = POINT()
    GetCursorPos(&pt)

    // The standard "right-click on tray" idiom: SetForegroundWindow before
    // TrackPopupMenu so dismiss-on-click-outside actually works.
    SetForegroundWindow(parent)
    _ = TrackPopupMenu(
        menu,
        UINT(TPM_RIGHTBUTTON | TPM_BOTTOMALIGN),
        pt.x, pt.y,
        0,
        parent,
        nil
    )
    PostMessageW(parent, UINT(WM_NULL), 0, 0)
}

/// Called from the WM_COMMAND switch when the menu items fire.
func handleTrayCommand(id: WORD, parent: HWND?) {
    switch id {
    case ID_TRAY_RECORD:
        // Reuse the existing main-button code path.
        if appState.isMixing { return }
        sendRecordButtonClick(parent: parent)

    case ID_TRAY_SHOW:
        showMainWindow(parent: parent)

    case ID_TRAY_REVEAL:
        revealLastSession()

    case ID_TRAY_UPDATES:
        startUpdateCheck(parent: parent)

    case ID_TRAY_QUIT:
        removeTrayIcon()
        DestroyWindow(parent)

    default:
        break
    }
}

// MARK: - Helpers used by the tray menu

func showMainWindow(parent: HWND?) {
    guard let parent else { return }
    ShowWindow(parent, SW_SHOW)
    SetForegroundWindow(parent)
}

func sendRecordButtonClick(parent: HWND?) {
    // Synthesize a click on the existing Record button so the state
    // machine stays in one place (handleCommand in MainWindow.swift).
    PostMessageW(parent, UINT(WM_COMMAND), WPARAM(ID_RECORD_BTN), 0)
}

func revealLastSession() {
    let target = appState.mergedFile ?? appState.sessionPath
    guard let url = target else { return }
    url.path.withWide { wpath in
        "open".withWide { wop in
            _ = ShellExecuteW(nil, wop, wpath, nil, nil, Int32(SW_SHOWNORMAL))
        }
    }
}
#endif
