import Foundation
import IOKit.hid

/// IOHIDManager wrapper for the controller's vendor HID interface (usage 0).
///
/// Callbacks are delivered on the main run loop.
public final class HIDLogoTransport {
    public var onConnectionChange: ((Bool) -> Void)?
    public var onInputReport: (([UInt8]) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var started = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        stop()
    }

    public var isConnected: Bool { device != nil }

    public func start() {
        guard !started else { return }
        started = true
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Int(DeviceIdentity.vendorID),
            kIOHIDProductIDKey: Int(DeviceIdentity.productID),
            kIOHIDDeviceUsageKey: DeviceIdentity.hidDeviceUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDLogoTransport>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDLogoTransport>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            guard let context else { return }
            let transport = Unmanaged<HIDLogoTransport>.fromOpaque(context).takeUnretainedValue()
            if let sender, let device = transport.device,
               Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue() != device { return }
            transport.onInputReport?(Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("IOHIDManagerOpen failed: 0x%08x", result)
        }
    }

    public func stop() {
        guard started else { return }
        started = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        device = nil
    }

    /// Sends one 128-byte output report. Safe to call from a background queue.
    @discardableResult
    public func send(_ report: [UInt8]) -> IOReturn {
        guard let device else { return kIOReturnNoDevice }
        return report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
        }
    }

    private func attach(_ device: IOHIDDevice) {
        guard self.device == nil else { return }
        self.device = device
        onConnectionChange?(true)
    }

    private func detach(_ device: IOHIDDevice) {
        guard self.device == device else { return }
        self.device = nil
        // Another matching interface may still be present (e.g. two controllers).
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let next = devices.first(where: { $0 != device }) {
            self.device = next
            return
        }
        onConnectionChange?(false)
    }
}
