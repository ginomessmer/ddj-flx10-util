import FLX10Kit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            LabeledContent("Utility Version", value: appVersion)
            LabeledContent("Firmware Version", value: model.firmwareVersion ?? "*.**")
            LabeledContent("USB ID", value: String(format: "%04X:%04X", DeviceIdentity.vendorID, DeviceIdentity.productID))
            Section {
                Text("An independent replacement for the DDJ-FLX10 Setup utility and DDJ-FLX10 Image Transfer Tool. Not affiliated with AlphaTheta Corporation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
