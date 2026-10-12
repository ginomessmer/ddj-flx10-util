import Foundation

/// HID output-report framing used to store a DJ logo on the controller.
///
/// Every report is 128 bytes, sent with `IOHIDDeviceSetReport(kIOHIDReportTypeOutput, reportID: 0)`.
/// Byte 0 is always 0x00 and byte 1 is the command.
///
/// Recovered from `MainComponent::buttonClicked`, `MainComponent::inputCallBack` and
/// `MainComponent::CommandThread::run` in DDJ-FLX10_ImageTransferTool 1.0.0.
public enum LogoProtocol {
    public static let reportLength = 128
    public static let inputReportLength = 64

    /// The logo is a 240×240 JPEG.
    public static let displaySize = 240
    /// Maximum JPEG payload the original tool will copy into its transfer buffer (0x2A400).
    public static let maxPayloadLength = 0x2A400

    /// Payload bytes carried by the first data report (after a 9-byte header).
    public static let firstChunkLength = 119
    /// Payload bytes carried by each following data report (after a 6-byte header).
    public static let chunkLength = 122

    public enum Command: UInt8 {
        /// Request: `[00 D0 01 len24le]` starts a transfer, `[00 D0 00]` starts a delete.
        case request = 0xD0
        /// Executes the delete after the device has acknowledged the delete request.
        case deleteExecute = 0xD7
        /// Image data report.
        case data = 0xD1
    }

    /// Byte 1 of a 64-byte input report.
    public enum Response: UInt8 {
        /// Device ready; advances the request handshake (sent twice before data/delete).
        case ready = 0xD8
        case transferAck = 0xDC
        case transferNak = 0xDD
        case deleteAck = 0xDE
        case deleteNak = 0xDF
    }

    public static func transferRequest(payloadLength: Int) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[1] = Command.request.rawValue
        report[2] = 0x01
        report[3] = UInt8(truncatingIfNeeded: payloadLength)
        report[4] = UInt8(truncatingIfNeeded: payloadLength >> 8)
        report[5] = UInt8(truncatingIfNeeded: payloadLength >> 16)
        return report
    }

    public static func deleteRequest() -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[1] = Command.request.rawValue
        return report
    }

    public static func deleteExecute() -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[1] = Command.deleteExecute.rawValue
        return report
    }

    public static func packetCount(payloadLength: Int) -> Int {
        guard payloadLength > firstChunkLength else { return 1 }
        let remaining = payloadLength - firstChunkLength
        return 1 + (remaining + chunkLength - 1) / chunkLength
    }

    /// Splits a payload into data reports.
    ///
    /// First report:  `[00 D1 idx16le=1 count16le len24le payload[0..<119]]`
    /// Later reports: `[00 D1 idx16le count16le payload[...122 bytes]]`
    /// Indices are 1-based; unused trailing bytes are zero.
    public static func dataReports(for payload: [UInt8]) -> [[UInt8]] {
        let count = packetCount(payloadLength: payload.count)
        var reports: [[UInt8]] = []
        reports.reserveCapacity(count)
        var offset = 0
        for index in 1...count {
            var report = [UInt8](repeating: 0, count: reportLength)
            report[1] = Command.data.rawValue
            report[2] = UInt8(truncatingIfNeeded: index)
            report[3] = UInt8(truncatingIfNeeded: index >> 8)
            report[4] = UInt8(truncatingIfNeeded: count)
            report[5] = UInt8(truncatingIfNeeded: count >> 8)
            let headerLength: Int
            let capacity: Int
            if index == 1 {
                report[6] = UInt8(truncatingIfNeeded: payload.count)
                report[7] = UInt8(truncatingIfNeeded: payload.count >> 8)
                report[8] = UInt8(truncatingIfNeeded: payload.count >> 16)
                headerLength = 9
                capacity = firstChunkLength
            } else {
                headerLength = 6
                capacity = chunkLength
            }
            let length = min(capacity, payload.count - offset)
            if length > 0 {
                report.replaceSubrange(headerLength..<(headerLength + length), with: payload[offset..<(offset + length)])
                offset += length
            }
            reports.append(report)
        }
        return reports
    }
}
