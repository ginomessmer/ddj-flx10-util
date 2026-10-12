import AppKit
import FLX10Kit
import SwiftUI

@main
struct FLX10UtilityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("FLX10 Utility", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 500)
        }
        .defaultSize(width: 780, height: 560)
        .commands { AppCommands(model: model) }

        Settings {
            PreferencesView()
                .environment(model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Image…") { model.chooseImage() }
                .keyboardShortcut("o")
                .disabled(model.isLogoBusy)
        }

        CommandGroup(after: .sidebar) {
            ForEach(Array(Pane.allCases.enumerated()), id: \.element) { index, pane in
                Button(pane.title) { model.selectedPane = pane }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }

        CommandMenu("Controller") {
            Button("Send Logo to \(DeviceIdentity.displayName)") { model.sendLogo() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSendLogo)
            Button("Remove Logo from \(DeviceIdentity.displayName)…") {
                model.selectedPane = .logo
                model.isConfirmingLogoRemoval = true
            }
            .disabled(!model.canDeleteLogo)
            Divider()
            Button("Send All Settings") { model.sendAllSettings() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.isConnected)
            Button("Restore Default Settings") { model.resetSettings() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running via `swift run` starts as a background process; make it a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
