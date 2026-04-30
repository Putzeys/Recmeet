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
        installTrayIcon(parent: hwnd)
        startUpdateCheck(parent: hwnd)
        return 0

    case WM_TRAYICON:
        // lParam carries the actual mouse event from the shell.
        let mouseMsg = UINT(lParam & 0xFFFF)
        switch Int32(mouseMsg) {
        case WM_LBUTTONUP:
            // Single click toggles main window visibility.
            if IsWindowVisible(hwnd) {
                ShowWindow(hwnd, SW_HIDE)
            } else {
                showMainWindow(parent: hwnd)
            }
        case WM_RBUTTONUP, WM_CONTEXTMENU:
            showTrayPopupMenu(parent: hwnd)
        default:
            break
        }
        return 0

    case UINT(WM_CLOSE):
        // X button hides — quit only via the tray menu.
        ShowWindow(hwnd, SW_HIDE)
        return 0

    case WM_UPDATE_AVAILABLE:
        handleUpdateAvailable(parent: hwnd)
        return 0

    case UINT(WM_COMMAND):
        let id = LOWORD(wParam)
        let notif = HIWORD(wParam)
        handleCommand(id: id, notification: notif)
        return 0

    case UINT(WM_HSCROLL):
        let source = HWND(bitPattern: Int(lParam))
        if source != nil && source == appState.hwndGainSlider {
            updateGainFromSlider()
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
        if bothCaptured, let session = appState.sessionPath {
            appState.statusText = "Saved. Choose mix volumes…"
            refreshUI()
            presentMergeDialog(parent: hwnd, sessionPath: session)
        } else {
            appState.statusText = "Saved."
            refreshUI()
        }
        return 0

    case WM_MIX_DONE:
        appState.isMixing = false
        if let merged = appState.mergedFile {
            appState.statusText = "Mixed → \(merged.lastPathComponent)"
        }
        refreshUI()
        return 0

    case WM_OP_FAILED:
        refreshUI()
        return 0

    case UINT(WM_DESTROY):
        removeTrayIcon()
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

    // Output folder section.
    _ = make("STATIC", "Output folder",
             style: 0, x: 20, y: 204, w: 200, h: 18)

    appState.hwndOutputLabel = make("STATIC", appState.outputDir.path,
                                    style: 0, x: 20, y: 226, w: 320, h: 18)

    appState.hwndOpenFolderBtn = make("BUTTON", "Open folder",
                                      style: 0,
                                      x: 350, y: 222, w: 100, h: 26,
                                      id: ID_OPEN_FOLDER_BTN)

    // Record button + elapsed label.
    appState.hwndRecordBtn = make("BUTTON", "Record",
                                  style: DWORD(BS_DEFPUSHBUTTON),
                                  x: 20, y: 268, w: 280, h: 38,
                                  id: ID_RECORD_BTN)

    appState.hwndElapsedLabel = make("STATIC", "00:00:00",
                                     style: 0,
                                     x: 320, y: 276, w: 130, h: 24)

    // Status line.
    appState.hwndStatusLabel = make("STATIC", appState.statusText,
                                    style: 0,
                                    x: 20, y: 320, w: 430, h: 18)
}

// MARK: - Command routing

private func handleCommand(id: WORD, notification: WORD) {
    // Tray-menu IDs route through their own handler so MainWindow keeps
    // its switch focused on its child controls.
    switch id {
    case ID_TRAY_RECORD, ID_TRAY_SHOW, ID_TRAY_REVEAL, ID_TRAY_UPDATES, ID_TRAY_QUIT:
        handleTrayCommand(id: id, parent: appState.hwndMain)
        return
    default:
        break
    }

    switch id {
    case ID_RECORD_BTN:
        if appState.isMixing { return }
        if appState.isRecording {
            startStopRequested(start: false)
        } else {
            startStopRequested(start: true)
        }

    case ID_MIC_CHECK:
        let v = SendMessageW(appState.hwndMicCheck, UINT(BM_GETCHECK), 0, 0)
        appState.captureMic = (v == BST_CHECKED)
        refreshUI()

    case ID_SYS_CHECK:
        let v = SendMessageW(appState.hwndSysCheck, UINT(BM_GETCHECK), 0, 0)
        appState.captureSystem = (v == BST_CHECKED)
        refreshUI()

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

func refreshUI() {
    let actionLabel: String
    if appState.isMixing {
        actionLabel = "Mixing…"
    } else if appState.isRecording {
        actionLabel = "Stop"
    } else {
        actionLabel = "Record"
    }
    setControlText(appState.hwndRecordBtn, actionLabel)
    EnableWindow(appState.hwndRecordBtn, !appState.isMixing)

    setControlText(appState.hwndStatusLabel, appState.statusText)
    setControlText(appState.hwndOutputLabel, appState.outputDir.path)
    setControlText(appState.hwndGainLabel, "\(appState.gainPercent)%")

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
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            appLog("session dir created: \(session.path)")
        } catch {
            appLog("FAILED creating session dir: \(error)")
            appState.statusText = "Folder error: \(error.localizedDescription)"
            refreshUI()
            return
        }
        appState.sessionPath = session
        appState.mergedFile = nil

        let captureMic = appState.captureMic
        let captureSystem = appState.captureSystem
        let device = appState.selectedDevice
        let gain = Float(appState.gainPercent) / 100

        appLog("startStopRequested(start: true)")
        appLog("  captureMic=\(captureMic) captureSystem=\(captureSystem)")
        appLog("  device=\(device?.name ?? "<default>") gain=\(gain)")
        appLog("  available device count=\(appState.devices.count)")
        for d in appState.devices {
            appLog("    device: '\(d.name)' channels=\(d.inputChannels) default=\(d.isDefault)")
        }

        appState.isRecording = true
        appState.startTime = Date()
        appState.statusText = "Starting…"
        refreshUI()

        Task.detached {
            appLog("worker: Task.detached entered")
            do {
                // Start mic + system in PARALLEL, not sequentially. Sequential
                // start gave the mic a head-start of ~100-200ms before
                // loopback got going (especially after we added the render
                // keepalive), and the mixer aligning frame 0 of each track
                // baked that gap right into the merged audio.
                try await withThrowingTaskGroup(of: Void.self) { group in
                    if captureMic {
                        group.addTask {
                            appLog("worker: starting MicRecorder")
                            let m = MicRecorder(outputDir: session, device: device, gain: gain)
                            try m.start()
                            appLog("worker: MicRecorder OK (rate=\(m.sampleRate) ch=\(m.channels))")
                            appState.mic = m
                        }
                    }
                    if captureSystem {
                        group.addTask {
                            appLog("worker: starting SystemRecorder")
                            let s = SystemRecorder(outputDir: session)
                            try await s.start()
                            appLog("worker: SystemRecorder OK")
                            appState.system = s
                        }
                    }
                    try await group.waitForAll()
                }
                appLog("worker: posting WM_RECORD_STARTED")
                _ = PostMessageW(main, WM_RECORD_STARTED, 0, 0)
            } catch let comError as COMError {
                let hex = String(format: "0x%08X", UInt32(bitPattern: Int32(comError.hr)))
                appLog("worker: COMError thrown — hr=\(hex) ctx='\(comError.context)'")
                appState.isRecording = false
                appState.statusText = "Failed: \(comError) — see app.log"
                appState.mic?.stop()
                appState.mic = nil
                appState.system = nil
                _ = PostMessageW(main, WM_OP_FAILED, 0, 0)
            } catch {
                appLog("worker: error thrown — \(type(of: error)) \(error)")
                appLog("  localizedDescription: \(error.localizedDescription)")
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

/// Called by MergeWindow when the user picks Merge or Don't Merge.
func mergeDecisionMade(merge: Bool, micVolume: Float, systemVolume: Float, keepTracks: Bool) {
    guard let session = appState.sessionPath else { return }
    let main = appState.hwndMain

    if !merge {
        appState.statusText = "Saved (separate tracks kept)."
        refreshUI()
        return
    }

    appState.isMixing = true
    appState.statusText = "Mixing…"
    refreshUI()

    Task.detached {
        do {
            let opts = SessionMixer.Options(
                micVolume: micVolume,
                systemVolume: systemVolume,
                keepSeparateTracks: keepTracks
            )
            let url = try await SessionMixer.merge(sessionDir: session, options: opts)
            appState.mergedFile = url
        } catch {
            appState.statusText = "Mix failed: \(error.localizedDescription)"
        }
        _ = PostMessageW(main, WM_MIX_DONE, 0, 0)
    }
}
#endif
