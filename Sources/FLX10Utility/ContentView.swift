import FLX10Kit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            Divider()
            TabView {
                LogoView()
                    .tabItem { Label("DJ Logo", systemImage: "photo") }
                SettingsView()
                    .tabItem { Label("Controller", systemImage: "slider.horizontal.3") }
                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
            .padding()
        }
        .frame(width: 560, height: 560)
    }
}

private struct ConnectionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(model.isConnected ? "\(DeviceIdentity.displayName) connected" : "\(DeviceIdentity.displayName) not connected")
                .font(.callout.weight(.medium))
            Spacer()
            if let firmware = model.firmwareVersion {
                Text("Firmware \(firmware)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct StatusText: View {
    let status: AppModel.Status

    var body: some View {
        switch status {
        case .none:
            EmptyView()
        case .info(let text):
            Text(text).foregroundStyle(.secondary)
        case .success(let text):
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .error(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
