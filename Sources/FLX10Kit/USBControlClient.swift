import CFLX10USB
import Foundation
import IOKit

/// Vendor control requests on the controller's default pipe.
public struct USBControlClient: Sendable {
    public struct RequestError: LocalizedError, Sendable {
        public let code: IOReturn
        public var errorDescription: String? {
            code == kIOReturnNoDevice
                ? "\(DeviceIdentity.displayName) is not connected."
                : String(format: "USB request failed (0x%08x).", UInt32(bitPattern: code))
        }
    }

    public let vendorID: UInt16
    public let productID: UInt16

    public init(vendorID: UInt16 = DeviceIdentity.vendorID, productID: UInt16 = DeviceIdentity.productID) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public var isConnected: Bool {
        flx10_usb_device_count(vendorID, productID) > 0
    }

    public func apply(_ setting: ControllerSetting, value: UInt8) throws {
        let result = flx10_usb_control_request(vendorID, productID, 0x40, 0x03, UInt16(value) << 8, setting.selector, nil, 0, nil)
        guard result == kIOReturnSuccess else { throw RequestError(code: result) }
    }

    public func apply(_ settings: ControllerSettings) throws {
        for setting in ControllerSetting.allCases {
            try apply(setting, value: settings.deviceValue(for: setting))
        }
    }

    /// Firmware version, formatted like the original About tab ("%x.%.2x").
    public func firmwareVersion() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 2)
        var transferred: UInt32 = 0
        let result = buffer.withUnsafeMutableBytes { raw in
            flx10_usb_control_request(vendorID, productID, 0xC0, 0x00, 0, 0xC001, raw.baseAddress, 2, &transferred)
        }
        guard result == kIOReturnSuccess else { throw RequestError(code: result) }
        return Self.formatFirmware(buffer)
    }

    static func formatFirmware(_ bytes: [UInt8]) -> String {
        String(format: "%x.%.2x", bytes[0], bytes[1])
    }
}
