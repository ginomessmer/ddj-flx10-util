import FLX10Kit
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("DJ software", selection: $model.settings.software) {
                    Text("rekordbox").tag(DJSoftware.rekordbox)
                    Text("Serato DJ Pro or other software").tag(DJSoftware.seratoDJPro)
                }
            } footer: {
                Text(model.settings.software == .rekordbox
                     ? "rekordbox configures the controller itself. Its options are in rekordbox’s preferences."
                     : "Controller options in this app are sent to the \(DeviceIdentity.displayName) over USB.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Controller") {
                LabeledContent("Model", value: DeviceIdentity.displayName)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.isConnected ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(model.isConnected ? "Connected" : "Not Connected")
                    }
                }
                LabeledContent("Firmware", value: model.firmwareVersion ?? "—")
                LabeledContent("USB ID") {
                    Text(String(format: "%04X:%04X", DeviceIdentity.vendorID, DeviceIdentity.productID))
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }

            Section {
                LabeledContent {
                    Button("Send Now") { model.sendAllSettings() }
                        .disabled(!model.isConnected)
                } label: {
                    Text("Send all settings")
                    Text("The controller can’t report its current options. Send them again if they’ve been changed elsewhere.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct JogDisplayPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControllerSettingsForm {
            Section {
                Picker("Jog ring color", selection: $model.settings.jogRingColor) {
                    Text("Mode 1").tag(JogRingColor.mode1)
                    Text("Mode 2").tag(JogRingColor.mode2)
                    Text("Mode 3").tag(JogRingColor.mode3)
                }
                Picker("Time display", selection: $model.settings.timeMode) {
                    Text("Elapsed").tag(TimeMode.elapsed)
                    Text("Remaining").tag(TimeMode.remaining)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: Binding(
                    get: { model.settings.virtualDeckMode == .on },
                    set: { model.settings.virtualDeckMode = $0 ? .on : .off }
                )) {
                    Text("Virtual deck mode")
                    Text("Shows the hot cue indicator on the jog display.")
                }
            }
        }
    }
}

struct PerformancePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControllerSettingsForm {
            Section("Slip Mode") {
                Toggle(isOn: Binding(
                    get: { model.settings.slipModeFlashing == .enable },
                    set: { model.settings.slipModeFlashing = $0 ? .enable : .disable }
                )) {
                    Text("Flash while slip mode is on")
                }
                Picker("SLIP button", selection: $model.settings.slipButtonLED) {
                    Text("Lit").tag(SlipButtonLED.light)
                    Text("Blinking").tag(SlipButtonLED.blink)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: Binding(
                    get: { model.settings.faderStartSync == .on },
                    set: { model.settings.faderStartSync = $0 ? .on : .off }
                )) {
                    Text("Turn on SYNC when Fader Start begins")
                }
            } header: {
                Text("Fader Start")
            } footer: {
                Text("Fader Start begins playback when you move a channel fader or the crossfader while holding SHIFT.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct RecordingPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ControllerSettingsForm {
            Section {
                Picker(selection: $model.settings.recOut) {
                    Text("Include microphone").tag(RecOut.withMic)
                    Text("Exclude microphone").tag(RecOut.withoutMic)
                } label: {
                    Text("REC OUT")
                    Text("Sets whether the microphone is mixed into the recording output.")
                }
                .pickerStyle(.radioGroup)
            }
        }
    }
}

/// Shared chrome for panes that write controller options: rekordbox notice, offline footer,
/// and disabling the options while rekordbox owns them.
private struct ControllerSettingsForm<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            if model.settings.software == .rekordbox {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Managed by rekordbox")
                                .font(.headline)
                            Text("Change these options in rekordbox’s preferences instead.")
                                .foregroundStyle(.secondary)
                            Button("Use Serato DJ Pro or Other Software") {
                                model.settings.software = .seratoDJPro
                            }
                            .buttonStyle(.link)
                        }
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title2)
                    }
                    .padding(.vertical, 4)
                }
            }

            Group { content }
                .disabled(model.settings.software == .rekordbox)

            if !model.isConnected {
                Section {
                } footer: {
                    Label("Changes are saved and sent when the \(DeviceIdentity.displayName) connects.", systemImage: "cable.connector")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("General") {
    GeneralPane()
        .environment(AppModel.preview())
        .frame(width: 560, height: 520)
}

#Preview("Jog Display") {
    JogDisplayPane()
        .environment(AppModel.preview())
        .frame(width: 560, height: 420)
}

#Preview("Performance") {
    PerformancePane()
        .environment(AppModel.preview())
        .frame(width: 560, height: 460)
}

#Preview("Performance – rekordbox") {
    PerformancePane()
        .environment(AppModel.preview(software: .rekordbox))
        .frame(width: 560, height: 560)
}

#Preview("Recording – not connected") {
    RecordingPane()
        .environment(AppModel.preview(connected: false))
        .frame(width: 560, height: 360)
}
