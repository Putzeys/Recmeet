# recmeet

Native desktop app + CLI to record **microphone + system audio**
simultaneously on **macOS and Windows**, with no virtual audio drivers
required. Built for long meetings where you just want clean audio for
transcription.

- Pure Swift on both platforms, single small binary, zero runtime deps
- macOS: **ScreenCaptureKit** for system audio (no BlackHole/Loopback/Soundflower)
- Windows: **WASAPI loopback** (the OS-native one)
- 30-minute chunked WAVs so you can record for hours, crash-safe
- Post-stop merge dialog with mic/system volume sliders (CleanShot-style)
- Native UI on each platform (SwiftUI on Mac, Win32 on Windows)

## Install

### macOS — Homebrew (recommended)

```sh
brew install --cask Putzeys/recmeet/recmeet
```

Brew downloads the DMG, strips the macOS quarantine flag, and installs
`recmeet.app` into `/Applications` — no Gatekeeper *"can't be verified"*
dialog. Upgrades happen via `brew upgrade --cask recmeet`.

### macOS — direct download

- **[recmeet-macos.dmg](https://github.com/Putzeys/Recmeet/releases/latest/download/recmeet-macos.dmg)** — double-click → drag `recmeet` onto Applications → eject → launch from Launchpad.
- [recmeet-macos.zip](https://github.com/Putzeys/Recmeet/releases/latest/download/recmeet-macos.zip) (alternative)

### Windows

- **[recmeet-windows.zip](https://github.com/Putzeys/Recmeet/releases/latest/download/recmeet-windows.zip)** — unzip → double-click `recmeet.exe`.

Once the app is installed, future updates happen **inside the app**: it
checks GitHub on launch, prompts you on a new release, and applies the
update with a single click.

### First-launch warnings (these are normal)

These builds are **ad-hoc signed**, not Apple-notarized or Authenticode-signed
— the OS doesn't recognise them as coming from a paid developer
account. Standard fix:

**macOS** (the dialog says *"…can't be verified for malicious software"*):
- **Open** *System Settings → Privacy & Security*, scroll to the bottom,
  and click **Open Anyway** next to the recmeet entry. Re-launch the app
  / DMG.
- **Or via Terminal**, strip the quarantine flag once:
  ```bash
  xattr -dr com.apple.quarantine ~/Downloads/recmeet-macos.dmg
  xattr -dr com.apple.quarantine /Applications/recmeet.app
  ```

**Windows** (SmartScreen says *"Windows protected your PC"*):
- Click **More info → Run anyway**. SmartScreen remembers your choice
  for this binary.

After the first launch, the auto-updater handles future versions
without re-triggering these warnings.

## Requirements

- macOS 13 Ventura or newer (ScreenCaptureKit audio capture requires it)
- Swift 5.9+ toolchain (`xcode-select --install` is enough)

## Build

```bash
git clone <this-repo>
cd recmeet
swift build -c release
cp .build/release/recmeet /usr/local/bin/   # optional
```

## First run

The first time you record, macOS will prompt for:

1. **Microphone** — granted via popup
2. **Screen Recording** — required for system audio, even though we capture no video.
   You may need to: open *System Settings → Privacy & Security → Screen Recording*,
   enable `recmeet`, then re-run.

## Usage

```bash
# List input devices
recmeet devices

# Record to ~/Recordings/recmeet/<timestamp>/
recmeet record

# Pick a specific mic (substring match) and a custom folder
recmeet record --mic "MacBook" --output ~/Meetings/

# Mic only / system only
recmeet record --no-system
recmeet record --no-mic
```

Press `Ctrl+C` to stop. Output:

```
~/Recordings/recmeet/2026-04-29T14-30-00Z/
├── meta.json
├── mic_000.wav        (30 min chunks)
├── mic_001.wav
├── system_000.wav
└── system_001.wav
```

## Why two tracks instead of mixed?

For transcription you usually want to feed Whisper (or similar) only your
mic — it gives cleaner attribution and avoids feedback from the system mix.
You can always merge the two tracks afterwards in any audio editor or with
`ffmpeg -i mic_000.wav -i system_000.wav -filter_complex amix=inputs=2 mixed.wav`.

## Privacy

recmeet is a local-only tool. Concretely:

- **No network calls**, ever. The binary makes zero outbound connections —
  no telemetry, no analytics, no cloud upload, no auto-update. You can
  verify with `lsof` or Little Snitch.
- **No video is captured.** Screen Recording permission is required only
  because Apple's `ScreenCaptureKit` API for system audio is bundled
  inside a screen-capture stream. recmeet requests the absolute minimum
  (a 2×2 px, 1 fps video target) and discards every video frame.
- **Audio stays on disk.** Recordings are written only to the folder you
  pick. No copies, no cache, no thumbnails.
- **Microphone is active only while recording.** The capture engine starts
  on the Record button and stops on Stop. There is no background
  listening, no wake-word, no buffering between sessions.
- **Source is small and auditable** — under ~1k lines of Swift across
  capture, mixing, and UI. Search for `URLSession`, `URL(string:`, or
  `http` — you will find none in the recording paths.

If any of the above ever stops being true, that is a bug. See
[SECURITY.md](SECURITY.md) for how to report it.

## Windows

A Windows CLI build is available (the SwiftUI app is macOS-only for now;
a separate cross-platform GUI lands in v0.3).

- Same Swift codebase, conditionally compiled with `#if os(Windows)`
- System audio uses **WASAPI loopback** — the OS-native one, no virtual
  audio driver required
- Microphone uses WASAPI capture against the chosen endpoint

```cmd
swift build -c release --product recmeet
.\.build\release\recmeet.exe devices
.\.build\release\recmeet.exe record --output C:\Recordings
```

## Roadmap

- [ ] `--format m4a` — encode chunks to AAC on stop
- [ ] `recmeet merge <session>` — re-mix from CLI
- [x] Windows CLI port (WASAPI loopback)
- [ ] Windows GUI (v0.3 — SwiftCrossUI vs WinUI host TBD)
- [ ] Optional Whisper transcription pipeline

## License

MIT
