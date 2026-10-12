import Foundation

/// Drives `LogoTransferMachine` over a `HIDLogoTransport`.
///
/// All public methods and callbacks run on the main thread; only the data phase streams reports
/// from a background queue, as the original's CommandThread did.
public final class LogoTransferService {
    public var onOutcome: ((LogoTransferMachine.Outcome) -> Void)?
    public var onProgress: ((Double) -> Void)?

    private let transport: HIDLogoTransport
    private var machine = LogoTransferMachine()
    private var payload: [UInt8] = []
    private var timeout: DispatchWorkItem?
    private let sendQueue = DispatchQueue(label: "FLX10Utility.logo-send", qos: .userInitiated)

    public init(transport: HIDLogoTransport) {
        self.transport = transport
    }

    public var isBusy: Bool { machine.isBusy }

    public func transfer(jpeg: Data) {
        payload = Array(jpeg)
        run(machine.startTransfer(payloadLength: payload.count))
    }

    public func deleteLogo() {
        run(machine.startDelete())
    }

    public func handle(inputReport: [UInt8]) {
        run(machine.receive(inputReport))
    }

    public func deviceDisconnected() {
        run(machine.timedOut())
    }

    private func run(_ effects: [LogoTransferMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .sendReport(let report):
                if report[1] == LogoProtocol.Command.request.rawValue { armTimeout() }
                let result = transport.send(report)
                if result != kIOReturnSuccess { NSLog("IOHIDDeviceSetReport failed: 0x%08x", result) }
            case .beginDataPhase:
                streamPayload()
            case .complete(let outcome):
                timeout?.cancel()
                timeout = nil
                onOutcome?(outcome)
            }
        }
    }

    private func streamPayload() {
        let reports = LogoProtocol.dataReports(for: payload)
        let transport = transport
        sendQueue.async { [weak self] in
            for (index, report) in reports.enumerated() {
                let result = transport.send(report)
                if result != kIOReturnSuccess { NSLog("IOHIDDeviceSetReport failed: 0x%08x", result) }
                if index % 32 == 0 || index == reports.count - 1 {
                    let progress = Double(index + 1) / Double(reports.count)
                    DispatchQueue.main.async { self?.onProgress?(progress) }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.run(self.machine.dataPhaseFinished())
            }
        }
    }

    private func armTimeout() {
        timeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timeout = nil
            self.run(self.machine.timedOut())
        }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + LogoTransferMachine.timeout, execute: item)
    }
}
