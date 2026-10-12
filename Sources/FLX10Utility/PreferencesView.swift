import FLX10Kit
import SwiftUI

/// The app's Settings window (⌘,). Controller options live in the main window; this holds
/// app behaviour only.
struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.applySettingsOnConnect) {
                    Text("Send settings automatically when the \(DeviceIdentity.displayName) connects")
                    Text("The controller can’t report its current options, so this app restores the ones you chose each time it connects.")
                }
            }
            Section {
                LabeledContent {
                    Button("Restore Defaults…") { isConfirmingReset = true }
                } label: {
                    Text("Controller settings")
                    Text("Return every controller option to the original Setup utility’s default.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Restore the default controller settings?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) { model.resetSettings() }
        } message: {
            Text("Your DJ software choice is kept.")
        }
    }
}

#Preview {
    PreferencesView()
        .environment(AppModel.preview())
}
