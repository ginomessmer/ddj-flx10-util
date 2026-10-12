import FLX10Kit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .navigationTitle(model.selectedPane?.title ?? "FLX10 Utility")
                .navigationSubtitle(model.connectionDescription)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { alert in
            if let retry = alert.retry {
                Button("Try Again") { retry() }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        #if DEBUG
        .task { DebugSnapshots.runIfRequested(model: model) }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedPane ?? .logo {
        case .general: GeneralPane()
        case .logo: LogoPane()
        case .jogDisplay: JogDisplayPane()
        case .performance: PerformancePane()
        case .recording: RecordingPane()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedPane) {
            DeviceCard()
                .listRowSeparator(.hidden)
                .selectionDisabled()

            Section {
                row(.general)
                row(.logo)
            }
            Section("Controller") {
                row(.jogDisplay)
                row(.performance)
                row(.recording)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ pane: Pane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            PaneIcon(symbol: pane.symbol, tint: pane.tint)
        }
        .tag(pane)
    }
}

/// The controller "account card" at the top of the sidebar.
private struct DeviceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "dial.medium.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(model.isConnected ? Color.accentColor : .secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: Circle())
                Circle()
                    .fill(model.isConnected ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(DeviceIdentity.displayName)
                    .font(.headline)
                Text(model.isConnected ? "Connected" : "Not Connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(DeviceIdentity.displayName), \(model.isConnected ? "connected" : "not connected")")
    }
}

#Preview("Connected") {
    ContentView()
        .environment(AppModel.preview(withLogo: true))
        .frame(width: 780, height: 560)
}

#Preview("Not connected") {
    ContentView()
        .environment(AppModel.preview(connected: false))
        .frame(width: 780, height: 560)
}
