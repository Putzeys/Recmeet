import SwiftCrossUI
import Foundation

struct ContentView: View {
    @State var state = RecorderState()

    @Environment(\.chooseFile) var chooseFile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("recmeet")
                Spacer()
                if state.isRecording {
                    Text("● \(state.elapsedFormatted)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Microphone")
                Toggle("Record microphone", isOn: $state.captureMic)
                    .toggleStyle(.switch)

                if !state.devices.isEmpty {
                    Picker(of: state.devices.map { $0.name }, selection: $state.selectedDeviceName)
                }

                HStack {
                    Text("Gain")
                    Slider(value: $state.gain, in: 0...2)
                    Text("\(Int(state.gain * 100))%")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("System audio")
                Toggle("Record system audio (loopback)", isOn: $state.captureSystem)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Output folder")
                HStack {
                    Text(state.outputDir.path)
                    Spacer()
                    Button("Choose…") {
                        Task {
                            if let url = await chooseFile(
                                title: "Choose output folder",
                                allowSelectingFiles: false,
                                allowSelectingDirectories: true
                            ) {
                                state.outputDir = url
                            }
                        }
                    }
                }
            }

            Button(state.isRecording ? "Stop" : "Record") {
                Task { await state.toggle() }
            }

            if state.isMixing {
                Text("Mixing…")
            }

            if let err = state.errorMessage {
                Text(err)
            }

            if let mixed = state.mergedFile, !state.isRecording, !state.isMixing {
                Text("Mixed → \(mixed.lastPathComponent)")
            }
        }
        .padding(20)
    }
}
