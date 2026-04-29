import Foundation
import Dispatch
import RecmeetCore

// MARK: - Argv parsing

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    let txt = """
    recmeet — simple meeting audio recorder (mic + system audio)

    Usage:
      recmeet devices
          List input devices.

      recmeet record [--mic NAME] [--output DIR] [--no-system] [--no-mic]
          Start recording. Press Ctrl+C to stop.
          --mic NAME      Substring match against device name. Default: system default.
          --output DIR    Output folder. Default: ~/Recordings/recmeet/<timestamp>/
          --no-system     Skip system-audio capture.
          --no-mic        Skip microphone capture.

    Output: WAV chunks of 30 minutes each, named mic_NNN.wav and system_NNN.wav.
    """
    FileHandle.standardError.write(Data((txt + "\n").utf8))
    exit(2)
}

guard let cmd = args.first else { usage() }
let rest = Array(args.dropFirst())

func opt(_ flag: String) -> String? {
    guard let i = rest.firstIndex(of: flag), i + 1 < rest.count else { return nil }
    return rest[i + 1]
}
func flag(_ name: String) -> Bool { rest.contains(name) }

// MARK: - Commands

@MainActor
func runDevices() {
    let inputs = AudioDevices.listInputs()
    if inputs.isEmpty {
        print("No input devices found.")
        return
    }
    for d in inputs {
        let star = d.isDefault ? "*" : " "
        print("\(star) [\(d.id)] \(d.name)  (\(d.inputChannels)ch)")
    }
    print("\n* = system default. Pass --mic with any substring of the name.")
}

@MainActor
func runRecord() async {
    let captureMic = !flag("--no-mic")
    let captureSystem = !flag("--no-system")
    guard captureMic || captureSystem else {
        Log.error("Both --no-mic and --no-system: nothing to record.")
        exit(2)
    }

    // Output directory
    let outputBase: URL
    if let custom = opt("--output") {
        outputBase = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
    } else {
        outputBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings/recmeet")
    }
    let stamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    let session = outputBase.appendingPathComponent(stamp)
    try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    Log.info("Session: \(session.path)")

    // Mic device
    var micDevice: AudioInputDevice?
    if captureMic, let name = opt("--mic") {
        guard let dev = AudioDevices.find(byName: name) else {
            Log.error("No input device matching '\(name)'. Run `recmeet devices` to list.")
            exit(1)
        }
        micDevice = dev
    }

    // Permissions
    if captureMic {
        guard await Permissions.requestMicrophone() else {
            Log.error("Microphone permission denied. Enable it in System Settings → Privacy & Security → Microphone.")
            exit(1)
        }
    }
    if captureSystem {
        guard await Permissions.ensureScreenRecording() else { exit(1) }
    }

    let mic: MicRecorder? = captureMic ? MicRecorder(outputDir: session, device: micDevice) : nil
    let system: SystemRecorder? = captureSystem ? SystemRecorder(outputDir: session) : nil

    do {
        try mic?.start()
        try await system?.start()
    } catch {
        Log.error("Failed to start: \(error.localizedDescription)")
        mic?.stop()
        await system?.stop()
        exit(1)
    }

    // Write meta.json
    var meta: [String: Any] = [
        "started_at": ISO8601DateFormatter().string(from: Date()),
        "mic": captureMic,
        "system": captureSystem,
    ]
    if let m = mic { meta["mic_device"] = micDevice?.name ?? "default"; meta["mic_sample_rate"] = m.sampleRate; meta["mic_channels"] = m.channels }
    if captureSystem { meta["system_sample_rate"] = 48000; meta["system_channels"] = 2 }
    if let json = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
        try? json.write(to: session.appendingPathComponent("meta.json"))
    }

    Log.info("Recording. Press Ctrl+C to stop.")

    // SIGINT → graceful stop. Ignore default handler so the dispatch source receives it.
    signal(SIGINT, SIG_IGN)
    let signalQueue = DispatchQueue(label: "recmeet.signal")
    let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    let sem = DispatchSemaphore(value: 0)
    sigSrc.setEventHandler { sem.signal() }
    sigSrc.resume()

    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
            sem.wait()
            cont.resume()
        }
    }

    Log.info("Stopping…")
    mic?.stop()
    await system?.stop()
    Log.info("Saved to \(session.path)")
}

// MARK: - Dispatch

switch cmd {
case "devices":
    await runDevices()
case "record":
    await runRecord()
case "-h", "--help", "help":
    usage()
default:
    usage()
}
