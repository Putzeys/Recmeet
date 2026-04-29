# Security policy

## Reporting a vulnerability

If you find a security issue in recmeet — anything that makes the app
behave outside its stated privacy guarantees, leaks recordings, or grants
unintended access to mic / screen — please **do not** open a public
issue.

Use GitHub's **"Report a vulnerability"** button on the repository's
*Security* tab to open a private advisory. That keeps the discussion
confidential until a fix ships.

Acknowledgement within 7 days, fix or mitigation within 30 days where
feasible. Coordinated disclosure is welcome.

## Threat model

recmeet is a single-user, local-only macOS audio recorder. It is **not**
designed to defend against:

- An attacker with root access on the same machine (they can read the
  output folder anyway).
- Compromise of the macOS TCC database itself.
- Side-channels via other apps that already have microphone or screen
  recording permission.

It **is** designed to ensure:

1. No audio leaves the device. There are zero network calls in the
   recording, mixing, or UI code paths.
2. No video frames are persisted, even though Screen Recording
   permission is required for system audio capture.
3. The microphone is engaged only between Record and Stop, and is
   released cleanly on every code path (including errors and crashes —
   `AVAudioEngine` releases the input on process exit).
4. Files are written only to the user-selected output folder. There is
   no temp directory, no cache, no shared container.

## Permissions, in plain terms

- **Microphone** (`NSMicrophoneUsageDescription`): used to record your
  voice.
- **Screen Recording** (`NSScreenCaptureUsageDescription`): used **only**
  to access `ScreenCaptureKit`'s system-audio stream. The accompanying
  video stream is configured at 2×2 px, 1 fps, and every video sample
  buffer is dropped without inspection. See
  [`SystemRecorder.swift`](Sources/RecmeetCore/Capture/SystemRecorder.swift).
- **User-Selected Read-Write Files** (entitlement): used so the output
  folder picker can write to a folder you explicitly choose.

No other entitlements are requested. The full set is visible in
[`recmeet.entitlements`](Sources/RecmeetApp/recmeet.entitlements).

## Verifying a build

Because recmeet is not Apple-notarized, the recommended path is to
build from source:

```bash
git clone <repo>
cd recmeet
./setup-codesign-identity.sh   # one-time, creates a self-signed dev identity
./build-app.sh --install
```

This produces an app signed with a self-signed certificate that lives
only in your login keychain. Each Mac generates its own identity — the
private key never leaves your machine and is not in this repository.

To audit before building, the network surface to check is small:

```bash
grep -RiE 'URLSession|URLRequest|http://|https://|NWConnection|CFNetwork' Sources/
```

The only matches you should see are the `<!DOCTYPE plist …>` headers in
`Info.plist` files (XML boilerplate, not a runtime fetch).

You will also see two `URL(string: "x-apple.systempreferences:…")` calls
in `Permissions.swift`. Those are deep-links that open the System
Settings app on the right pane when permissions are denied — they are
**not** network requests. The `x-apple.systempreferences:` scheme is
handled locally by the OS.

## What I do not promise

- This project is provided as-is under MIT, with no warranty (see
  `LICENSE`). It has not been independently audited.
- I am not a credentialed security researcher. If a real audit ever
  happens, results will be linked from this file.
