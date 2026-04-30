import SwiftUI
import AppKit
import RecmeetCore

struct MenuBarContent: View {
    @EnvironmentObject var vm: RecorderViewModel
    @EnvironmentObject var updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if vm.isRecording {
            Text("● Recording — \(vm.elapsedFormatted)")
                .foregroundStyle(.red)
            Divider()
        }

        Button(vm.isRecording ? "Stop Recording" : "Start Recording") {
            Task { await vm.toggle() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(vm.isMixing)

        Divider()

        Button("Show Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        if let merged = vm.mergedFile {
            Button("Reveal Last Recording") {
                NSWorkspace.shared.activateFileViewerSelecting([merged])
            }
        }

        Divider()

        Button("Check for Updates…") {
            Task { await updates.checkOnce() }
        }

        Divider()

        Button("Quit recmeet") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
