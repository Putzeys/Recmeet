import SwiftUI

@main
struct RecmeetApp: App {
    @StateObject private var vm = RecorderViewModel()
    @StateObject private var updates = UpdateChecker()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Menu bar entry — the canonical "always available" surface.
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(vm)
                .environmentObject(updates)
        } label: {
            // Status icon: filled red when recording, outline mic otherwise.
            Image(systemName: vm.isRecording ? "record.circle.fill" : "mic.circle")
                .foregroundStyle(vm.isRecording ? .red : .primary)
        }

        // Optional config window — hidden by default, opened from the menu.
        Window("recmeet", id: "main") {
            ContentView()
                .environmentObject(vm)
                .environmentObject(updates)
        }
        .windowResizability(.contentSize)
    }
}
