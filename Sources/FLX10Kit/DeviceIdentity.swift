import Foundation

/// USB identity of the Pioneer DJ / AlphaTheta DDJ-FLX10.
///
/// Both original tools match on these values: the image tool through an IOHIDManager matching
/// dictionary (VendorID, ProductID, DeviceUsage = 0), the setup framework through IOUSBDevice
/// idVendor/idProduct with bDeviceClass != 9.
public enum DeviceIdentity {
    public static let vendorID: UInt16 = 0x2B73
    public static let productID: UInt16 = 0x0041
    /// Top-level HID usage of the interface that carries the logo transfer reports.
    public static let hidDeviceUsage: Int = 0
    public static let displayName = "DDJ-FLX10"
}
