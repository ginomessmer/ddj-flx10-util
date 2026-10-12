import AppKit
import FLX10Kit
import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    struct Alert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var retry: (() -> Void)?
    }

    enum LogoActivity: Equatable {
        case idle
        case transferring(progress: Double)
        case deleting
        case succeeded(String)
    }

    // MARK: Device

    private(set) var isConnected = false
    private(set) var firmwareVersion: String?
    /// The vendor HID interface used for logo transfer is present.
    private(set) var logoInterfaceAvailable = false

    // MARK: Logo

    private(set) var logoPreview: CGImage?
    private(set) var logoFileName: String?
    private(set) var logoActivity: LogoActivity = .idle
    private(set) var logoJPEG: Data?
    /// The decoded source image, kept so the layout can be changed after choosing it.
    private(set) var logoSource: CGImage?
    var logoLayout: LogoLayout = .fit {
        didSet { if logoLayout != oldValue { renderLogo() } }
    }

    // MARK: Navigation

    var selectedPane: Pane? = .logo

    // MARK: Settings

    var settings: ControllerSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    var applySettingsOnConnect: Bool {
        didSet { if isLive { UserDefaults.standard.set(applySettingsOnConnect, forKey: Self.applyOnConnectKey) } }
    }

    var alert: Alert?
    var isConfirmingLogoRemoval = false

    private static let applyOnConnectKey = "applySettingsOnConnect"

    @ObservationIgnored private let transport = HIDLogoTransport()
    @ObservationIgnored private let logoService: LogoTransferService
    @ObservationIgnored private let usb = USBControlClient()
    @ObservationIgnored private let store = SettingsStore()
    @ObservationIgnored private let usbQueue = DispatchQueue(label: "FLX10Utility.usb", qos: .userInitiated)
    @ObservationIgnored private var presenceTimer: Timer?
    @ObservationIgnored private var successReset: DispatchWorkItem?

    /// False for previews: no IOKit, no persistence.
    @ObservationIgnored private let isLive: Bool

    init(startDevices: Bool = true) {
        isLive = startDevices
        settings = store.load()
        applySettingsOnConnect = UserDefaults.standard.object(forKey: Self.applyOnConnectKey) as? Bool ?? true
        logoService = LogoTransferService(transport: transport)

        transport.onConnectionChange = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnection() }
        }
        transport.onInputReport = { [weak self] report in
            MainActor.assumeIsolated { self?.logoService.handle(inputReport: report) }
        }
        logoService.onProgress = { [weak self] progress in
            MainActor.assumeIsolated {
                guard let self, case .transferring = self.logoActivity else { return }
                self.logoActivity = .transferring(progress: progress)
            }
        }
        logoService.onOutcome = { [weak self] outcome in
            MainActor.assumeIsolated { self?.finish(outcome) }
        }
        guard startDevices else { return }
        transport.start()

        // HID callbacks cover the logo interface; poll the USB device too so settings work even if
        // the HID interface is unavailable (e.g. claimed by another app).
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnection() }
        }
        refreshConnection()
    }

    // MARK: Connection

    var connectionDescription: String {
        guard isConnected else { return "Not Connected" }
        if let firmwareVersion { return "Connected · Firmware \(firmwareVersion)" }
        return "Connected"
    }

    private func refreshConnection() {
        let hid = transport.isConnected
        if hid != logoInterfaceAvailable { logoInterfaceAvailable = hid }
        let usb = self.usb
        usbQueue.async { [weak self] in
            let connected = hid || usb.isConnected
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.setConnected(connected) }
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        if connected {
            readFirmware()
            if applySettingsOnConnect { sendAllSettings(reportSuccess: false) }
        } else {
            firmwareVersion = nil
            logoService.deviceDisconnected()
        }
    }

    private func readFirmware() {
        let usb = self.usb
        usbQueue.async { [weak self] in
            let version = try? usb.firmwareVersion()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.firmwareVersion = version }
            }
        }
    }

    // MARK: Logo

    var isLogoBusy: Bool {
        switch logoActivity {
        case .transferring, .deleting: return true
        case .idle, .succeeded: return false
        }
    }

    var hasLogo: Bool { logoJPEG != nil }
    var canSendLogo: Bool { isConnected && logoInterfaceAvailable && hasLogo && !isLogoBusy }
    var canDeleteLogo: Bool { isConnected && logoInterfaceAvailable && !isLogoBusy }

    func chooseImage() {
        selectedPane = .logo
        let panel = NSOpenPanel()
        panel.title = "Choose a DJ Logo"
        panel.message = "Choose a BMP, JPEG, PNG or GIF image."
        panel.prompt = "Choose"
        panel.allowedContentTypes = LogoImageEncoder.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    func loadImage(from url: URL) {
        guard !isLogoBusy else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let image = try LogoImageEncoder.loadImage(at: url)
            logoSource = image
            logoFileName = url.lastPathComponent
            logoActivity = .idle
            // Square images look the same either way; otherwise start with the original's Fit.
            logoLayout = .fit
            renderLogo()
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            alert = Alert(title: "“\(url.lastPathComponent)” Can’t Be Used", message: error.localizedDescription)
        }
    }

    /// True when the source isn't square, so Fit and Fill differ.
    var logoHasLayoutChoice: Bool {
        guard let logoSource else { return false }
        return logoSource.width != logoSource.height
    }

    private func renderLogo() {
        guard let logoSource else { return }
        do {
            let result = try LogoImageEncoder.encode(image: logoSource, layout: logoLayout)
            logoPreview = result.preview
            logoJPEG = result.jpegData
        } catch {
            alert = Alert(title: "The Image Can’t Be Used", message: error.localizedDescription)
        }
    }

    func clearImage() {
        guard !isLogoBusy else { return }
        logoPreview = nil
        logoJPEG = nil
        logoSource = nil
        logoLayout = .fit
        logoFileName = nil
        logoActivity = .idle
    }

    func sendLogo() {
        guard canSendLogo, let jpeg = logoJPEG else { return }
        successReset?.cancel()
        logoActivity = .transferring(progress: 0)
        logoService.transfer(jpeg: jpeg)
    }

    func deleteLogo() {
        guard canDeleteLogo else { return }
        successReset?.cancel()
        logoActivity = .deleting
        logoService.deleteLogo()
    }

    private func finish(_ outcome: LogoTransferMachine.Outcome) {
        switch outcome {
        case .transferSucceeded:
            showSuccess("Sent to \(DeviceIdentity.displayName)")
        case .deleteSucceeded:
            showSuccess("Removed from \(DeviceIdentity.displayName)")
        case .transferFailed:
            logoActivity = .idle
            alert = Alert(
                title: "The Logo Couldn’t Be Sent",
                message: "The \(DeviceIdentity.displayName) didn’t accept the image. Make sure the controller stays connected, then try again.",
                retry: { [weak self] in self?.sendLogo() }
            )
        case .deleteFailed:
            logoActivity = .idle
            alert = Alert(
                title: "The Logo Couldn’t Be Removed",
                message: "The \(DeviceIdentity.displayName) didn’t confirm the deletion. Try again.",
                retry: { [weak self] in self?.deleteLogo() }
            )
        }
    }

    private func showSuccess(_ message: String) {
        logoActivity = .succeeded(message)
        let reset = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .succeeded = self.logoActivity else { return }
                self.logoActivity = .idle
            }
        }
        successReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: reset)
    }

    // MARK: Settings

    private func settingsChanged(from old: ControllerSettings) {
        guard isLive else { return }
        store.save(settings)
        let changed = ControllerSetting.allCases.filter { old.deviceValue(for: $0) != settings.deviceValue(for: $0) }
        guard !changed.isEmpty, isConnected else { return }
        send(changed.map { ($0, settings.deviceValue(for: $0)) }, reportSuccess: false)
    }

    func sendAllSettings(reportSuccess: Bool = true) {
        send(ControllerSetting.allCases.map { ($0, settings.deviceValue(for: $0)) }, reportSuccess: reportSuccess)
    }

    func resetSettings() {
        let software = settings.software
        var defaults = ControllerSettings()
        defaults.software = software
        settings = defaults
    }

    private func send(_ values: [(ControllerSetting, UInt8)], reportSuccess: Bool) {
        let usb = self.usb
        usbQueue.async { [weak self] in
            var failure: Error?
            for (setting, value) in values {
                do { try usb.apply(setting, value: value) } catch { failure = error; break }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let failure {
                        self.alert = Alert(
                            title: "Settings Couldn’t Be Sent",
                            message: failure.localizedDescription,
                            retry: { [weak self] in self?.sendAllSettings() }
                        )
                    } else if reportSuccess {
                        NSSound(named: "Glass")?.play()
                    }
                }
            }
        }
    }

    // MARK: Previews

    /// A model that never touches IOKit, for SwiftUI previews.
    static func preview(connected: Bool = true, software: DJSoftware = .seratoDJPro, withLogo: Bool = false, layout: LogoLayout = .fit) -> AppModel {
        let model = AppModel(startDevices: false)
        model.settings = ControllerSettings()
        model.isConnected = connected
        model.logoInterfaceAvailable = connected
        model.firmwareVersion = connected ? "1.05" : nil
        model.settings.software = software
        if withLogo {
            model.logoSource = previewArtwork()
            model.logoFileName = "My Logo.png"
            model.logoLayout = layout
            model.renderLogo()
        }
        return model
    }

    func previewActivity(_ activity: LogoActivity) -> AppModel {
        logoActivity = activity
        return self
    }

    private static func previewArtwork() -> CGImage {
        let context = CGContext(data: nil, width: 480, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 1, green: 0.45, blue: 0.1, alpha: 1), CGColor(red: 0.55, green: 0.1, blue: 0.9, alpha: 1)]
        let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 480, y: 320), options: [])
        context.setFillColor(CGColor(gray: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 170, y: 90, width: 140, height: 140))
        return context.makeImage()!
    }
}
