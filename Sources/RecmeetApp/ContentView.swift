import SwiftUI
import RecmeetCore

struct ContentView: View {
    @StateObject private var vm = RecorderViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            micSection
            systemSection
            outputSection

            recordButton

            if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if vm.sessionPath != nil, !vm.isRecording, !vm.showMergeSheet {
                HStack {
                    Text(vm.mergedFile != nil ? "Mixed:" : "Last session:")
                    Text((vm.mergedFile ?? vm.sessionPath!).lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal") { vm.revealSession() }
                }
                .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { vm.refreshDevices() }
        .sheet(isPresented: $vm.showMergeSheet) {
            MergeSheet(vm: vm)
        }
    }

    private var header: some View {
        HStack {
            Text("recmeet").font(.title2.bold())
            Spacer()
            if vm.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(vm.elapsedSeconds.isMultiple(of: 2) ? 1 : 0.3)
                Text(vm.elapsedFormatted)
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
        }
    }

    private var micSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Record microphone", isOn: $vm.captureMic)
                    .toggleStyle(.switch)

                Picker("Device", selection: $vm.selectedDeviceID) {
                    ForEach(vm.devices) { d in
                        Text(d.name + (d.isDefault ? " (default)" : ""))
                            .tag(d.id)
                    }
                }
                .disabled(!vm.captureMic || vm.isRecording)

                HStack {
                    Image(systemName: "speaker.wave.1.fill").foregroundStyle(.secondary)
                    Slider(value: $vm.gain, in: 0...2)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    Text("\(Int(vm.gain * 100))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!vm.captureMic)

                VUMeter(level: vm.micLevel)
                    .frame(height: 10)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Microphone", systemImage: "mic.fill")
        }
    }

    private var systemSection: some View {
        GroupBox {
            Toggle("Record system audio (loopback)", isOn: $vm.captureSystem)
                .toggleStyle(.switch)
                .disabled(vm.isRecording)
        } label: {
            Label("System audio", systemImage: "speaker.wave.2.fill")
        }
    }

    private var outputSection: some View {
        GroupBox {
            HStack {
                Text(vm.outputDir.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { vm.pickFolder() }
                    .disabled(vm.isRecording)
            }
        } label: {
            Label("Output folder", systemImage: "folder.fill")
        }
    }

    private var recordButton: some View {
        Button {
            Task { await vm.toggle() }
        } label: {
            Label(vm.isRecording ? "Stop" : "Record",
                  systemImage: vm.isRecording ? "stop.circle.fill" : "record.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(vm.isRecording ? .red : .accentColor)
        .keyboardShortcut(.return, modifiers: [.command])
    }
}

struct VUMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                LinearGradient(
                    colors: [.green, .green, .yellow, .red],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * CGFloat(min(1, max(0, level))))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}
