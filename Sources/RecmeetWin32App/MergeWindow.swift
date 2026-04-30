#if os(Windows)
import WinSDK
import Foundation

// MARK: - Merge dialog state

let MERGE_CLASS_NAME = "RecmeetMergeDialog"

let ID_MERGE_MIC_SLIDER: WORD = 200
let ID_MERGE_SYS_SLIDER: WORD = 201
let ID_MERGE_KEEP:       WORD = 202
let ID_MERGE_DONT:       WORD = 203
let ID_MERGE_GO:         WORD = 204

final class MergeDialogState {
    var hwnd: HWND?
    var parent: HWND?
    var sessionPath: URL?

    var micVolume: Int = 100
    var systemVolume: Int = 100
    var keepTracks: Bool = false

    var hwndMicSlider: HWND?
    var hwndMicLabel: HWND?
    var hwndSysSlider: HWND?
    var hwndSysLabel: HWND?
    var hwndKeepCheck: HWND?
    var hwndGoBtn: HWND?
    var hwndDontBtn: HWND?
}

let mergeState = MergeDialogState()

// MARK: - Window class

let mergeWndProc: WNDPROC = { hwnd, msg, wParam, lParam -> LRESULT in
    switch msg {
    case UINT(WM_CREATE):
        mergeState.hwnd = hwnd
        createMergeControls(in: hwnd)
        return 0

    case UINT(WM_HSCROLL):
        let source = HWND(bitPattern: Int(lParam))
        if source == mergeState.hwndMicSlider {
            updateMergeMicLabel()
        } else if source == mergeState.hwndSysSlider {
            updateMergeSysLabel()
        }
        return 0

    case UINT(WM_COMMAND):
        let id = LOWORD(wParam)
        switch id {
        case ID_MERGE_GO:
            captureMergeChoices()
            dismissMerge(merge: true)
        case ID_MERGE_DONT:
            captureMergeChoices()
            dismissMerge(merge: false)
        case ID_MERGE_KEEP:
            // Just track UI state; we read it again on submit anyway.
            break
        default:
            break
        }
        return 0

    case UINT(WM_CLOSE):
        // Title-bar X = Don't Merge.
        captureMergeChoices()
        dismissMerge(merge: false)
        return 0

    default:
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
}

func registerMergeWindowClass(_ hInstance: HINSTANCE?) -> Bool {
    var result: Bool = false
    MERGE_CLASS_NAME.withWide { wcls in
        var wcex = WNDCLASSEXW()
        wcex.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wcex.style = UINT(CS_HREDRAW | CS_VREDRAW)
        wcex.lpfnWndProc = mergeWndProc
        wcex.hInstance = hInstance
        wcex.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        wcex.hbrBackground = HBRUSH(bitPattern: UInt(COLOR_BTNFACE) + 1)
        wcex.lpszClassName = wcls
        result = (RegisterClassExW(&wcex) != 0)
    }
    return result
}

// MARK: - Public API

/// Disable the parent, create the merge dialog window, and let the message loop
/// drive it. The dialog calls `mergeDecisionMade(...)` on the main module
/// before destroying itself.
func presentMergeDialog(parent: HWND?, sessionPath: URL) {
    mergeState.parent = parent
    mergeState.sessionPath = sessionPath
    EnableWindow(parent, false)

    MERGE_CLASS_NAME.withWide { wcls in
        "Mix audio".withWide { wtitle in
            // Use the standard overlapped style set so all WS_* bits stay
            // inside Int32 (WS_POPUP = 0x80000000 imports as UInt32 and trips
            // type inference). The owned-parent + EnableWindow(parent,false)
            // pair already gives us the modal behaviour we want.
            let hwnd = CreateWindowExW(
                DWORD(WS_EX_DLGMODALFRAME),
                wcls,
                wtitle,
                DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_VISIBLE),
                CW_USEDEFAULT, CW_USEDEFAULT,
                480, 240,
                parent,
                nil,
                GetModuleHandleW(nil),
                nil
            )
            if hwnd == nil {
                EnableWindow(parent, true)
                return
            }
            UpdateWindow(hwnd)
            SetForegroundWindow(hwnd)
        }
    }
}

// MARK: - Internals

private func createMergeControls(in parent: HWND?) {
    let hInst = GetModuleHandleW(nil)

    func make(_ cls: String, _ text: String, style: DWORD,
              x: Int32, y: Int32, w: Int32, h: Int32, id: WORD = 0) -> HWND? {
        cls.withWide { wcls in
            text.withWide { wtxt in
                CreateWindowExW(
                    0, wcls, wtxt,
                    style | DWORD(WS_CHILD | WS_VISIBLE),
                    x, y, w, h, parent,
                    HMENU(bitPattern: UInt(id)), hInst, nil
                )
            }
        }
    }

    _ = make("STATIC",
             "Merge audio to adjust the volume of each track separately:",
             style: 0, x: 16, y: 14, w: 440, h: 18)

    _ = make("STATIC", "Microphone volume:",
             style: 0, x: 16, y: 46, w: 130, h: 18)
    TRACKBAR_CLASS.withCString(encodedAs: UTF16.self) { wcls in
        mergeState.hwndMicSlider = CreateWindowExW(
            0, wcls, nil,
            DWORD(WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS),
            150, 42, 230, 28, parent,
            HMENU(bitPattern: UInt(ID_MERGE_MIC_SLIDER)), hInst, nil
        )
    }
    SendMessageW(mergeState.hwndMicSlider, UINT(TBM_SETRANGE), 1, MAKELPARAM(0, 100))
    SendMessageW(mergeState.hwndMicSlider, UINT(TBM_SETPOS), 1, LPARAM(100))
    mergeState.hwndMicLabel = make("STATIC", "100%",
                                   style: 0, x: 388, y: 46, w: 60, h: 18)

    _ = make("STATIC", "Computer audio volume:",
             style: 0, x: 16, y: 80, w: 130, h: 18)
    TRACKBAR_CLASS.withCString(encodedAs: UTF16.self) { wcls in
        mergeState.hwndSysSlider = CreateWindowExW(
            0, wcls, nil,
            DWORD(WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS),
            150, 76, 230, 28, parent,
            HMENU(bitPattern: UInt(ID_MERGE_SYS_SLIDER)), hInst, nil
        )
    }
    SendMessageW(mergeState.hwndSysSlider, UINT(TBM_SETRANGE), 1, MAKELPARAM(0, 100))
    SendMessageW(mergeState.hwndSysSlider, UINT(TBM_SETPOS), 1, LPARAM(100))
    mergeState.hwndSysLabel = make("STATIC", "100%",
                                   style: 0, x: 388, y: 80, w: 60, h: 18)

    mergeState.hwndKeepCheck = make("BUTTON", "Keep separate tracks",
                                    style: DWORD(BS_AUTOCHECKBOX),
                                    x: 16, y: 116, w: 200, h: 22,
                                    id: ID_MERGE_KEEP)

    mergeState.hwndDontBtn = make("BUTTON", "Don't Merge",
                                  style: 0,
                                  x: 220, y: 158, w: 110, h: 32,
                                  id: ID_MERGE_DONT)

    mergeState.hwndGoBtn = make("BUTTON", "Merge Audio",
                                style: DWORD(BS_DEFPUSHBUTTON),
                                x: 340, y: 158, w: 120, h: 32,
                                id: ID_MERGE_GO)
}

private func updateMergeMicLabel() {
    let pos = SendMessageW(mergeState.hwndMicSlider, UINT(TBM_GETPOS), 0, 0)
    setControlText(mergeState.hwndMicLabel, "\(pos)%")
}

private func updateMergeSysLabel() {
    let pos = SendMessageW(mergeState.hwndSysSlider, UINT(TBM_GETPOS), 0, 0)
    setControlText(mergeState.hwndSysLabel, "\(pos)%")
}

private func captureMergeChoices() {
    mergeState.micVolume = Int(
        SendMessageW(mergeState.hwndMicSlider, UINT(TBM_GETPOS), 0, 0))
    mergeState.systemVolume = Int(
        SendMessageW(mergeState.hwndSysSlider, UINT(TBM_GETPOS), 0, 0))
    mergeState.keepTracks = (
        SendMessageW(mergeState.hwndKeepCheck, UINT(BM_GETCHECK), 0, 0) == BST_CHECKED)
}

private func dismissMerge(merge: Bool) {
    let parent = mergeState.parent
    let micVol = Float(mergeState.micVolume) / 100
    let sysVol = Float(mergeState.systemVolume) / 100
    let keep = mergeState.keepTracks

    if let hwnd = mergeState.hwnd {
        DestroyWindow(hwnd)
    }
    mergeState.hwnd = nil
    EnableWindow(parent, true)
    SetForegroundWindow(parent)

    mergeDecisionMade(
        merge: merge,
        micVolume: micVol,
        systemVolume: sysVol,
        keepTracks: keep
    )
}
#endif
