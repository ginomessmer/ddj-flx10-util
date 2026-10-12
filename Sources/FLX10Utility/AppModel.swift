import AppKit
import Combine
import FLX10Kit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case none
        case info(String)
        case success(String)
        case error(String)
    }

    @Published private(set) var isConnected = false
    @Published private(set) var firmwareVersion: String?
    /// The vendor HID interface used for logo transfer is present.
    @Published private(set) var logoInterfaceAvailable = false

    @Published private(set) var logoPreview: CGImage?
    @Published private(set) var logoFileName: String?
    @Published private(set) var logoStatus: Status = .none
    @Published private(set) var transferProgress: Double?
    @Published private(set) var isLogoBusy = false

    @Published var settings: ControllerSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published private(set) var settingsStatus: Status = .none
    @Published var applySettingsOnConnect: Bool {
        didSet { UserDefaults.standard.set(applySettingsOnConnect, forKey: Self.applyOnConnectKey) }
    }

    private static let applyOnConnectKey = "applySettingsOnConnect"

    private let transport = HIDLogoTransport()
    private let logoService: LogoTransferService
    private let usb = USBControlClient()
    private let store = SettingsStore()
    private let usbQueue = DispatchQueue(label: "FLX10Utility.usb", qos: .userInitiated)
    private var logoJPEG: Data?
    private var presenceTimer: Timer?

    init() {
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
            MainActor.assumeIsolated { self?.transferProgress = progress }
        }
        logoService.onOutcome = { [weak self] outcome in
            MainActor.assumeIsolated { self?.finish(outcome) }
        }
        transport.start()

        // HID callbacks cover the logo interface; poll the USB device too so settings work even if
        // the HID interface is unavailable (e.g. claimed by another app).
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnection() }
        }
        refreshConnection()
    }

    // MARK: Connection

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
            if applySettingsOnConnect { applyAllSettings(announce: false) }
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

    func loadImage(from url: URL) {
        guard !isLogoBusy else { return }
        do {
            let result = try LogoImageEncoder.encode(fileAt: url)
            logoPreview = result.preview
            logoJPEG = result.jpegData
            logoFileName = url.lastPathComponent
            logoStatus = .none
        } catch {
            logoStatus = .error(error.localizedDescription)
        }
    }

    var canTransfer: Bool { isConnected && logoJPEG != nil && !isLogoBusy && logoInterfaceAvailable }
    var canDelete: Bool { isConnected && !isLogoBusy && logoInterfaceAvailable }

    func transferLogo() {
        guard canTransfer, let jpeg = logoJPEG else { return }
        isLogoBusy = true
        transferProgress = 0
        logoStatus = .info("Transferring image…")
        logoService.transfer(jpeg: jpeg)
    }

    func deleteLogo() {
        guard canDelete else { return }
        isLogoBusy = true
        transferProgress = nil
        logoStatus = .info("Deleting…")
        logoService.deleteLogo()
    }

    private func finish(_ outcome: LogoTransferMachine.Outcome) {
        isLogoBusy = false
        transferProgress = nil
        switch outcome {
        case .transferSucceeded: logoStatus = .success("Transfer success.")
        case .transferFailed: logoStatus = .error("Transfer failed.")
        case .deleteSucceeded: logoStatus = .success("File deleted.")
        case .deleteFailed: logoStatus = .error("Delete failed.")
        }
    }

    // MARK: Settings

    private func settingsChanged(from old: ControllerSettings) {
        store.save(settings)
        let changed = ControllerSetting.allCases.filter { old.deviceValue(for: $0) != settings.deviceValue(for: $0) }
        guard !changed.isEmpty, isConnected else { return }
        let values = changed.map { ($0, settings.deviceValue(for: $0)) }
        send(values, announce: false)
    }

    func applyAllSettings(announce: Bool = true) {
        send(ControllerSetting.allCases.map { ($0, settings.deviceValue(for: $0)) }, announce: announce)
    }

    private func send(_ values: [(ControllerSetting, UInt8)], announce: Bool) {
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
                        self.settingsStatus = .error(failure.localizedDescription)
                    } else if announce {
                        self.settingsStatus = .success("Settings sent to the controller.")
                    } else {
                        self.settingsStatus = .none
                    }
                }
            }
        }
    }
}
