#if os(Windows)
import WinSDK
import Foundation
import RecmeetCore
import RecmeetCoreWindows

// MARK: - Control IDs and custom messages

let ID_MIC_CHECK:        WORD = 100
let ID_SYS_CHECK:        WORD = 101
let ID_DEVICE_COMBO:     WORD = 102
let ID_GAIN_SLIDER:      WORD = 103
let ID_OPEN_FOLDER_BTN:  WORD = 104
let ID_RECORD_BTN:       WORD = 105
let ID_MIC_MIX_SLIDER:   WORD = 106
let ID_SYS_MIX_SLIDER:   WORD = 107
let ID_KEEP_TRACKS:      WORD = 108
let ID_DONT_MERGE_BTN:   WORD = 109

let ID_TIMER_ELAPSED: UINT_PTR = 1

// WM_USER is imported as Int32; promote before adding offsets.
let WM_RECORD_STARTED: UINT = UINT(WM_USER) + 1
let WM_RECORD_STOPPED: UINT = UINT(WM_USER) + 2
let WM_MIX_DONE:       UINT = UINT(WM_USER) + 3
let WM_OP_FAILED:      UINT = UINT(WM_USER) + 4

// MARK: - Window proc

let windowProc: WNDPROC = { hwnd, msg, wParam, lParam -> LRESULT in
    switch msg {
    case UINT(WM_CREATE):
        appState.hwndMain = hwnd
        createControls(parent: hwnd)
        refreshUI()
        return 0

    case UINT(WM_COMMAND):
        let id = LOWORD(wParam)
        let notif = HIWORD(wParam)
        handleCommand(id: id, notification: notif)
        return 0

    case UINT(WM_HSCROLL):
        let source = HWND(bitPattern: Int(lParam))
        if source != nil {
            if source == appState.hwndGainSlider {
                updateGainFromSlider()
            } else if source == appState.hwndMicMixSlider {
                updateMicMixFromSlider()
            } else if source == appState.hwndSysMixSlider {
                updateSysMixFromSlider()
            }
        }
        return 0

    case UINT(WM_TIMER):
        if wParam == ID_TIMER_ELAPSED {
            setControlText(appState.hwndElapsedLabel, appState.elapsedFormatted)
        }
        return 0

    case WM_RECORD_STARTED:
        appState.isRecording = true
        appState.startTime = Date()
        SetTimer(hwnd, ID_TIMER_ELAPSED, 1000, nil)
        appState.statusText = "Recording…"
        refreshUI()
        return 0

    case WM_RECORD_STOPPED:
        KillTimer(hwnd, ID_TIMER_ELAPSED)
        appState.isRecording = false
        let bothCaptured = (wParam != 0)
        appState.bothCapturedInLastSession = bothCaptured
        if bothCaptured {
            appState.hasRecordedSession = true
            appState.statusText = "Recording saved. Adjust mix volumes and click Mix Audio."
        } else {
            appState.hasRecordedSession = false
            appState.statusText = "Saved."
        }
        refreshUI()
        return 0

    case WM_MIX_DONE:
        appState.isMixing = false
        appState.hasRecordedSession = false
        if let merged = appState.mergedFile {
            appState.statusText = "Mixed → \(merged.lastPathComponent)"
        }
        refreshUI()
        return 0

    case WM_OP_FAILED:
        refreshUI()
        return 0

    case UINT(WM_DESTROY):
        PostQuitMessage(0)
        return 0

    default:
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
}

// MARK: - Control creation

private func createControls(parent: HWND?) {
    let hInst = GetModuleHandleW(nil)

    func make(_ cls: String, _ text: String, style: DWORD,
              x: Int32, y: Int32, w: Int32, h: Int32, id: WORD = 0) -> HWND? {
        cls.withWide { wcls in
            text.withWide { wtxt in
                CreateWindowExW(
                    0,
                    wcls,
                    wtxt,
                    style | DWORD(WS_CHILD | WS_VISIBLE),
                    x, y, w, h,
                    parent,
                    HMENU(bitPattern: UInt(id)),
                    hInst,
                    nil
                )
            }
        }
    }

    // Microphone section.
    _ = make("STATIC", "Microphone",
             style: 0, x: 20, y: 16, w: 200, h: 18)

    appState.hwndMicCheck = make("BUTTON", "Record microphone",
                                 style: DWORD(BS_AUTOCHECKBOX),
                                 x: 20, y: 38, w: 200, h: 22,
                                 id: ID_MIC_CHECK)
    SendMessageW(appState.hwndMicCheck, UINT(BM_SETCHECK),
                 WPARAM(BST_CHECKED), 0)

    appState.hwndDeviceCombo = make("COMBOBOX", "",
                                    style: DWORD(CBS_DROPDOWNLIST | WS_VSCROLL),
                                    x: 20, y: 66, w: 420, h: 200,
                                    id: ID_DEVICE_COMBO)
    for device in appState.devices {
        device.name.withWide { wname in
            _ = SendMessageW(appState.hwndDeviceCombo,
                             UINT(CB_ADDSTRING), 0, ptrToLPARAM(wname))
        }
    }
    SendMessageW(appState.hwndDeviceCombo, UINT(CB_SETCURSEL),
                 WPARAM(appState.selectedDeviceIndex), 0)

    _ = make("STATIC", "Gain",
             style: 0, x: 20, y: 104, w: 60, h: 18)

    TRACKBAR_CLASS.withCString(encodedAs: UTF16.self) { wcls in
        appState.hwndGainSlider = CreateWindowExW(
            0, wcls, nil,
            DWORD(WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS),
            70, 100, 280, 28,
            parent,
            HMENU(bitPattern: UInt(ID_GAIN_SLIDER)),
            hInst,
            nil
        )
    }
    SendMessageW(appState.hwndGainSlider, UINT(TBM_SETRANGE), 1,
                 MAKELPARAM(0, 200))
    SendMessageW(appState.hwndGainSlider, UINT(TBM_SETPOS), 1,
                 LPARAM(appState.gainPercent))

    appState.hwndGainLabel = make("STATIC", "100%",
                                  style: 0,
                                  x: 360, y: 104, w: 60, h: 18)

    // System audio section.
    _ = make("STATIC", "System audio",
             style: 0, x: 20, y: 144, w: 200, h: 18)

    appState.hwndSysCheck = make("BUTTON", "Record system audio (loopback)",
                                 style: DWORD(BS_AUTOCHECKBOX),
                                 x: 20, y: 166, w: 320, h: 22,
                                 id: ID_SYS_CHECK)
    SendMessageW(appState.hwndSysCheck, UINT(BM_SETCHECK),
                 WPARAM(BST_CHECKED), 0)

    // Mix volumes (used after recording stops).
    _ = make("STATIC", "Mix volumes",
             style: 0, x: 20, y: 204, w: 200, h: 18)

    _ = make("STATIC", "Mic", style: 0, x: 20, y: 230, w: 50, h: 18)
    TRACKBAR_CLASS.withCString(encodedAs: UTF16.self) { wcls in
        appState.hwndMicMixSlider = CreateWindowExW(
            0, wcls, nil,
            DWORD(WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS),
            70, 226, 280, 28,
            parent,
            HMENU(bitPattern: UInt(ID_MIC_MIX_SLIDER)),
            hInst,
            nil
        )
    }
    SendMessageW(appState.hwndMicMixSlider, UINT(TBM_SETRANGE), 1, MAKELPARAM(0, 100))
    SendMessageW(appState.hwndMicMixSlider, UINT(TBM_SETPOS), 1, LPARAM(appState.micMixPercent))
    appState.hwndMicMixLabel = make("STATIC", "100%", style: 0, x: 360, y: 230, w: 60, h: 18)

    _ = make("STATIC", "System", style: 0, x: 20, y: 258, w: 50, h: 18)
    TRACKBAR_CLASS.withCString(encodedAs: UTF16.self) { wcls in
        appState.hwndSysMixSlider = CreateWindowExW(
            0, wcls, nil,
            DWORD(WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS),
            70, 254, 280, 28,
            parent,
            HMENU(bitPattern: UInt(ID_SYS_MIX_SLIDER)),
            hInst,
            nil
        )
    }
    SendMessageW(appState.hwndSysMixSlider, UINT(TBM_SETRANGE), 1, MAKELPARAM(0, 100))
    SendMessageW(appState.hwndSysMixSlider, UINT(TBM_SETPOS), 1, LPARAM(appState.systemMixPercent))
    appState.hwndSysMixLabel = make("STATIC", "100%", style: 0, x: 360, y: 258, w: 60, h: 18)

    appState.hwndKeepTracksCheck = make("BUTTON", "Keep separate tracks",
                                        style: DWORD(BS_AUTOCHECKBOX),
                                        x: 20, y: 286, w: 200, h: 22,
                                        id: ID_KEEP_TRACKS)

    // Output folder section.
    _ = make("STATIC", "Output folder",
             style: 0, x: 20, y: 322, w: 200, h: 18)

    appState.hwndOutputLabel = make("STATIC", appState.outputDir.path,
                                    style: 0, x: 20, y: 344, w: 320, h: 18)

    appState.hwndOpenFolderBtn = make("BUTTON", "Open folder",
                                      style: 0,
                                      x: 350, y: 340, w: 100, h: 26,
                                      id: ID_OPEN_FOLDER_BTN)

    // Action buttons + elapsed label.
    appState.hwndRecordBtn = make("BUTTON", "Record",
                                  style: DWORD(BS_DEFPUSHBUTTON),
                                  x: 20, y: 386, w: 200, h: 38,
                                  id: ID_RECORD_BTN)

    appState.hwndDontMergeBtn = make("BUTTON", "Don't Merge",
                                     style: 0,
                                     x: 230, y: 386, w: 110, h: 38,
                                     id: ID_DONT_MERGE_BTN)
    ShowWindow(appState.hwndDontMergeBtn, SW_HIDE)

    appState.hwndElapsedLabel = make("STATIC", "00:00:00",
                                     style: 0,
                                     x: 360, y: 394, w: 100, h: 24)

    // Status line.
    appState.hwndStatusLabel = make("STATIC", appState.statusText,
                                    style: 0,
                                    x: 20, y: 436, w: 440, h: 18)
}

// MARK: - Command routing

private func handleCommand(id: WORD, notification: WORD) {
    switch id {
    case ID_RECORD_BTN:
        // Three-state action button: Record → Stop → Mix Audio → Record.
        if appState.isMixing {
            return
        } else if appState.isRecording {
            startStopRequested(start: false)
        } else if appState.hasRecordedSession {
            mixRequested()
        } else {
            startStopRequested(start: true)
        }

    case ID_DONT_MERGE_BTN:
        dontMerge()

    case ID_MIC_CHECK:
        let v = SendMessageW(appState.hwndMicCheck, UINT(BM_GETCHECK), 0, 0)
        appState.captureMic = (v == BST_CHECKED)
        refreshUI()

    case ID_SYS_CHECK:
        let v = SendMessageW(appState.hwndSysCheck, UINT(BM_GETCHECK), 0, 0)
        appState.captureSystem = (v == BST_CHECKED)
        refreshUI()

    case ID_KEEP_TRACKS:
        let v = SendMessageW(appState.hwndKeepTracksCheck, UINT(BM_GETCHECK), 0, 0)
        appState.keepSeparateTracks = (v == BST_CHECKED)

    case ID_DEVICE_COMBO where notification == WORD(CBN_SELCHANGE):
        let idx = SendMessageW(appState.hwndDeviceCombo,
                               UINT(CB_GETCURSEL), 0, 0)
        if idx >= 0 {
            appState.selectedDeviceIndex = Int(idx)
        }

    case ID_OPEN_FOLDER_BTN:
        appState.outputDir.path.withWide { wpath in
            "open".withWide { wop in
                _ = ShellExecuteW(nil, wop, wpath, nil, nil, Int32(SW_SHOWNORMAL))
            }
        }

    default:
        break
    }
}

// MARK: - State updates

private func updateGainFromSlider() {
    let pos = SendMessageW(appState.hwndGainSlider, UINT(TBM_GETPOS), 0, 0)
    appState.gainPercent = Int(pos)
    appState.mic?.gain = Float(appState.gainPercent) / 100
    setControlText(appState.hwndGainLabel, "\(appState.gainPercent)%")
}

private func updateMicMixFromSlider() {
    let pos = SendMessageW(appState.hwndMicMixSlider, UINT(TBM_GETPOS), 0, 0)
    appState.micMixPercent = Int(pos)
    setControlText(appState.hwndMicMixLabel, "\(appState.micMixPercent)%")
}

private func updateSysMixFromSlider() {
    let pos = SendMessageW(appState.hwndSysMixSlider, UINT(TBM_GETPOS), 0, 0)
    appState.systemMixPercent = Int(pos)
    setControlText(appState.hwndSysMixLabel, "\(appState.systemMixPercent)%")
}

func refreshUI() {
    // Action button label cycles through Record → Stop → Mix Audio → Record.
    let actionLabel: String
    if appState.isMixing {
        actionLabel = "Mixing…"
    } else if appState.isRecording {
        actionLabel = "Stop"
    } else if appState.hasRecordedSession {
        actionLabel = "Mix Audio"
    } else {
        actionLabel = "Record"
    }
    setControlText(appState.hwndRecordBtn, actionLabel)
    EnableWindow(appState.hwndRecordBtn, !appState.isMixing)

    setControlText(appState.hwndStatusLabel, appState.statusText)
    setControlText(appState.hwndOutputLabel, appState.outputDir.path)
    setControlText(appState.hwndGainLabel, "\(appState.gainPercent)%")
    setControlText(appState.hwndMicMixLabel, "\(appState.micMixPercent)%")
    setControlText(appState.hwndSysMixLabel, "\(appState.systemMixPercent)%")

    // Don't Merge button only visible while we have a recorded session
    // waiting for a decision.
    let showDontMerge = appState.hasRecordedSession
        && appState.bothCapturedInLastSession
        && !appState.isMixing
    ShowWindow(appState.hwndDontMergeBtn, showDontMerge ? SW_SHOW : SW_HIDE)

    // Mix sliders + keep-tracks make sense only when there is a session
    // to act on. Outside that window we leave them visible-but-disabled.
    let mixActive = appState.hasRecordedSession
        && appState.bothCapturedInLastSession
        && !appState.isMixing
    EnableWindow(appState.hwndMicMixSlider,    mixActive)
    EnableWindow(appState.hwndSysMixSlider,    mixActive)
    EnableWindow(appState.hwndKeepTracksCheck, mixActive)

    // Recording controls disabled while a recording / mix is in flight.
    let recordable = !appState.isRecording && !appState.isMixing
    EnableWindow(appState.hwndMicCheck,    recordable)
    EnableWindow(appState.hwndSysCheck,    recordable)
    EnableWindow(appState.hwndDeviceCombo, recordable)
}

// MARK: - Recording lifecycle

private func startStopRequested(start: Bool) {
    let main = appState.hwndMain

    if start {
        guard appState.captureMic || appState.captureSystem else {
            appState.statusText = "Enable at least one source."
            refreshUI()
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let session = appState.outputDir.appendingPathComponent(stamp)
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        appState.sessionPath = session
        appState.mergedFile = nil

        let captureMic = appState.captureMic
        let captureSystem = appState.captureSystem
        let device = appState.selectedDevice
        let gain = Float(appState.gainPercent) / 100

        // Flip isRecording immediately so the button shows "Stop" and a
        // double-click can't kick off a second start. We don't have a Swift
        // MainActor executor wired into Win32's message loop, so we stay
        // off the main actor entirely and use PostMessage as the handshake.
        appState.isRecording = true
        appState.startTime = Date()
        appState.statusText = "Starting…"
        refreshUI()

        Task.detached {
            do {
                if captureMic {
                    let m = MicRecorder(outputDir: session, device: device, gain: gain)
                    try m.start()
                    appState.mic = m
                }
                if captureSystem {
                    let s = SystemRecorder(outputDir: session)
                    try await s.start()
                    appState.system = s
                }
                _ = PostMessageW(main, WM_RECORD_STARTED, 0, 0)
            } catch {
                appState.isRecording = false
                appState.statusText = "Failed: \(error.localizedDescription)"
                appState.mic?.stop()
                appState.mic = nil
                appState.system = nil
                _ = PostMessageW(main, WM_OP_FAILED, 0, 0)
            }
        }
    } else {
        guard appState.isRecording else { return }

        appState.isRecording = false
        appState.statusText = "Stopping…"
        refreshUI()

        let session = appState.sessionPath
        let mic = appState.mic
        let system = appState.system
        appState.mic = nil
        appState.system = nil
        appState.startTime = nil
        let bothCaptured = (mic != nil) && (system != nil)

        Task.detached {
            mic?.stop()
            await system?.stop()
            _ = PostMessageW(main, WM_RECORD_STOPPED, bothCaptured ? 1 : 0, 0)
        }
    }
}

private func mixRequested() {
    guard let session = appState.sessionPath else { return }
    let main = appState.hwndMain
    let micVol = Float(appState.micMixPercent) / 100
    let sysVol = Float(appState.systemMixPercent) / 100
    let keep = appState.keepSeparateTracks

    appState.isMixing = true
    appState.statusText = "Mixing…"
    refreshUI()

    Task.detached {
        do {
            let opts = SessionMixer.Options(
                micVolume: micVol,
                systemVolume: sysVol,
                keepSeparateTracks: keep
            )
            let url = try await SessionMixer.merge(sessionDir: session, options: opts)
            appState.mergedFile = url
        } catch {
            appState.statusText = "Mix failed: \(error.localizedDescription)"
        }
        _ = PostMessageW(main, WM_MIX_DONE, 0, 0)
    }
}

private func dontMerge() {
    appState.hasRecordedSession = false
    appState.statusText = "Saved (separate tracks kept)."
    refreshUI()
}
#endif
