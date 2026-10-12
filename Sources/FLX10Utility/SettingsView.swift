import FLX10Kit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Software", selection: $model.settings.software) {
                    Text("rekordbox").tag(DJSoftware.rekordbox)
                    Text("Serato DJ Pro / Other Software").tag(DJSoftware.seratoDJPro)
                }
                if model.settings.software == .rekordbox {
                    Text("When using with rekordbox, configure the settings from the rekordbox preferences.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                Section("Slip Mode") {
                    Picker("Slip Mode Flashing", selection: $model.settings.slipModeFlashing) {
                        Text("Enable").tag(SlipModeFlashing.enable)
                        Text("Disable").tag(SlipModeFlashing.disable)
                    }
                    .pickerStyle(.segmented)
                    Picker("Slip button LED while slip mode is on", selection: $model.settings.slipButtonLED) {
                        Text("Light is On").tag(SlipButtonLED.light)
                        Text("Blink").tag(SlipButtonLED.blink)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Fader Start") {
                    Toggle("Turn on SYNC on each deck when the Fader Start begins", isOn: Binding(
                        get: { model.settings.faderStartSync == .on },
                        set: { model.settings.faderStartSync = $0 ? .on : .off }
                    ))
                    Text("Fader Start is enabled when the Channel Fader or the CROSSFADER is moved while pressing the SHIFT button.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Display & Output") {
                    Picker("Jog Ring Color", selection: $model.settings.jogRingColor) {
                        Text("MODE 1").tag(JogRingColor.mode1)
                        Text("MODE 2").tag(JogRingColor.mode2)
                        Text("MODE 3").tag(JogRingColor.mode3)
                    }
                    Picker("Time Mode", selection: $model.settings.timeMode) {
                        Text("Elapsed").tag(TimeMode.elapsed)
                        Text("Remaining").tag(TimeMode.remaining)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Virtual Deck Mode: display HOT CUE INDICATOR", isOn: Binding(
                        get: { model.settings.virtualDeckMode == .on },
                        set: { model.settings.virtualDeckMode = $0 ? .on : .off }
                    ))
                    Picker("REC OUT", selection: $model.settings.recOut) {
                        Text("WITH MIC").tag(RecOut.withMic)
                        Text("WITHOUT MIC").tag(RecOut.withoutMic)
                    }
                }
            }
            .disabled(model.settings.software == .rekordbox)

            Section {
                Toggle("Send saved settings whenever the controller connects", isOn: $model.applySettingsOnConnect)
                HStack {
                    StatusText(status: model.settingsStatus)
                    Spacer()
                    Button("Send to Controller") { model.applyAllSettings() }
                        .disabled(!model.isConnected)
                }
            }
        }
        .formStyle(.grouped)
    }
}
