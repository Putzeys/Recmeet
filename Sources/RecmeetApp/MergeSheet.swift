import SwiftUI

struct MergeSheet: View {
    @ObservedObject var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Merge audio to adjust the volume of each track separately:")
                .font(.body)

            VStack(spacing: 10) {
                volumeRow(
                    label: "Microphone volume:",
                    value: $vm.micMergeVolume,
                    icon: "mic.fill"
                )
                volumeRow(
                    label: "Computer audio volume:",
                    value: $vm.systemMergeVolume,
                    icon: "speaker.wave.2.fill"
                )
            }

            HStack(spacing: 16) {
                Toggle("Keep separate tracks", isOn: $vm.keepSeparateTracks)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            if vm.isMixing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: vm.mixingProgress)
                        .progressViewStyle(.linear)
                    Text("Mixing… \(Int(vm.mixingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Toggle("Don't ask again", isOn: $vm.alwaysAutoMerge)
                    .toggleStyle(.checkbox)
                    .disabled(vm.isMixing)
                Spacer()
                Button("Don't Merge") { vm.skipMerge() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(vm.isMixing)
                Button("Merge Audio") {
                    Task { await vm.runMerge() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(vm.isMixing)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func volumeRow(label: String, value: Binding<Float>, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 170, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
    }
}
