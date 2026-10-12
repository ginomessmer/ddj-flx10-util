import CoreGraphics
import XCTest
@testable import FLX10Kit

final class LogoProtocolTests: XCTestCase {
    func testPacketCountMatchesOriginalFormula() {
        XCTAssertEqual(LogoProtocol.packetCount(payloadLength: 1), 1)
        XCTAssertEqual(LogoProtocol.packetCount(payloadLength: 119), 1)
        XCTAssertEqual(LogoProtocol.packetCount(payloadLength: 120), 2)
        XCTAssertEqual(LogoProtocol.packetCount(payloadLength: 119 + 122), 2)
        XCTAssertEqual(LogoProtocol.packetCount(payloadLength: 119 + 123), 3)
        XCTAssertEqual(LogoProtocol.packetCount(payloadLength: LogoProtocol.maxPayloadLength), 1 + (0x2A400 - 119 + 121) / 122)
    }

    func testTransferRequestLayout() {
        let report = LogoProtocol.transferRequest(payloadLength: 0x012345)
        XCTAssertEqual(report.count, 128)
        XCTAssertEqual(Array(report[0..<6]), [0x00, 0xD0, 0x01, 0x45, 0x23, 0x01])
        XCTAssertTrue(report[6...].allSatisfy { $0 == 0 })
    }

    func testDeleteReports() {
        XCTAssertEqual(Array(LogoProtocol.deleteRequest()[0..<3]), [0x00, 0xD0, 0x00])
        XCTAssertEqual(Array(LogoProtocol.deleteExecute()[0..<2]), [0x00, 0xD7])
    }

    func testDataReportsRoundTrip() {
        let payload = (0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        let reports = LogoProtocol.dataReports(for: payload)
        XCTAssertEqual(reports.count, 1 + Int((1000.0 - 119) / 122).advanced(by: 1))
        XCTAssertTrue(reports.allSatisfy { $0.count == 128 })

        let first = reports[0]
        XCTAssertEqual(Array(first[0..<9]), [0x00, 0xD1, 0x01, 0x00, UInt8(reports.count), 0x00, 0xE8, 0x03, 0x00])

        var reassembled: [UInt8] = Array(first[9..<128])
        for (offset, report) in reports.dropFirst().enumerated() {
            let index = offset + 2
            XCTAssertEqual(Array(report[0..<6]), [0x00, 0xD1, UInt8(index), 0x00, UInt8(reports.count), 0x00])
            reassembled += report[6..<128]
        }
        XCTAssertEqual(Array(reassembled[0..<payload.count]), payload)
        XCTAssertTrue(reassembled[payload.count...].allSatisfy { $0 == 0 })
    }
}

final class LogoTransferMachineTests: XCTestCase {
    private func report(_ response: LogoProtocol.Response) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes[1] = response.rawValue
        return bytes
    }

    func testSuccessfulTransfer() {
        var machine = LogoTransferMachine()
        XCTAssertEqual(machine.startTransfer(payloadLength: 10), [.sendReport(LogoProtocol.transferRequest(payloadLength: 10))])
        XCTAssertEqual(machine.receive(report(.ready)), [])
        XCTAssertEqual(machine.receive(report(.ready)), [.beginDataPhase])
        XCTAssertEqual(machine.state, .sending)
        XCTAssertEqual(machine.dataPhaseFinished(), [])
        XCTAssertEqual(machine.receive(report(.transferAck)), [])
        XCTAssertEqual(machine.receive(report(.transferAck)), [.complete(.transferSucceeded)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testNakFailsTransfer() {
        var machine = LogoTransferMachine()
        _ = machine.startTransfer(payloadLength: 10)
        _ = machine.receive(report(.ready))
        _ = machine.receive(report(.ready))
        _ = machine.dataPhaseFinished()
        XCTAssertEqual(machine.receive(report(.transferNak)), [])
        XCTAssertEqual(machine.receive(report(.transferAck)), [.complete(.transferFailed)])
    }

    func testResponseDuringStreamingFailsTransfer() {
        var machine = LogoTransferMachine()
        _ = machine.startTransfer(payloadLength: 10)
        _ = machine.receive(report(.ready))
        _ = machine.receive(report(.ready))
        XCTAssertEqual(machine.receive(report(.transferAck)), [])
        _ = machine.dataPhaseFinished()
        XCTAssertEqual(machine.state, .awaitingTransferResult)
        XCTAssertEqual(machine.receive(report(.transferAck)), [.complete(.transferFailed)])
    }

    func testDeleteSequence() {
        var machine = LogoTransferMachine()
        XCTAssertEqual(machine.startDelete(), [.sendReport(LogoProtocol.deleteRequest())])
        XCTAssertEqual(machine.receive(report(.ready)), [])
        XCTAssertEqual(machine.receive(report(.ready)), [.sendReport(LogoProtocol.deleteExecute())])
        XCTAssertEqual(machine.receive(report(.deleteAck)), [])
        XCTAssertEqual(machine.receive(report(.deleteAck)), [.complete(.deleteSucceeded)])
    }

    func testDeleteNak() {
        var machine = LogoTransferMachine()
        _ = machine.startDelete()
        _ = machine.receive(report(.ready))
        _ = machine.receive(report(.ready))
        XCTAssertEqual(machine.receive(report(.deleteNak)), [])
        XCTAssertEqual(machine.receive(report(.deleteAck)), [.complete(.deleteFailed)])
    }

    func testTimeout() {
        var machine = LogoTransferMachine()
        _ = machine.startTransfer(payloadLength: 10)
        XCTAssertEqual(machine.timedOut(), [.complete(.transferFailed)])
        _ = machine.startDelete()
        XCTAssertEqual(machine.timedOut(), [.complete(.deleteFailed)])
        XCTAssertEqual(machine.timedOut(), [])
    }

    func testShortOrUnknownReportsIgnored() {
        var machine = LogoTransferMachine()
        _ = machine.startTransfer(payloadLength: 10)
        XCTAssertEqual(machine.receive([0x00, 0xD8]), [])
        var unknown = report(.ready)
        unknown[1] = 0x42
        XCTAssertEqual(machine.receive(unknown), [])
        XCTAssertEqual(machine.state, .transferRequested)
    }
}

final class LogoImageEncoderTests: XCTestCase {
    func testFitRect() {
        XCTAssertEqual(LogoImageEncoder.fitRect(imageWidth: 480, imageHeight: 240, side: 240), CGRect(x: 0, y: 60, width: 240, height: 120))
        XCTAssertEqual(LogoImageEncoder.fitRect(imageWidth: 100, imageHeight: 400, side: 240), CGRect(x: 90, y: 0, width: 60, height: 240))
        XCTAssertEqual(LogoImageEncoder.fitRect(imageWidth: 50, imageHeight: 50, side: 240), CGRect(x: 0, y: 0, width: 240, height: 240))
    }

    func testEncodeProducesSquareJPEG() throws {
        let context = CGContext(data: nil, width: 300, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
        let result = try LogoImageEncoder.encode(image: context.makeImage()!)
        XCTAssertEqual(result.preview.width, 240)
        XCTAssertEqual(result.preview.height, 240)
        XCTAssertEqual(Array(result.jpegData.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThanOrEqual(result.jpegData.count, LogoProtocol.maxPayloadLength)
    }
}

final class ControllerSettingsTests: XCTestCase {
    func testDefaultsMatchOriginal() {
        let settings = ControllerSettings()
        XCTAssertEqual(settings.deviceValue(for: .slipModeFlashing), 1)
        XCTAssertEqual(settings.deviceValue(for: .slipButtonLED), 0)
        XCTAssertEqual(settings.deviceValue(for: .faderStartSync), 2)
        XCTAssertEqual(settings.deviceValue(for: .jogRingColor), 0)
        XCTAssertEqual(settings.deviceValue(for: .timeMode), 1)
        XCTAssertEqual(settings.deviceValue(for: .virtualDeckMode), 1)
        XCTAssertEqual(settings.deviceValue(for: .recOut), 0)
    }

    func testLegacyPlistImport() {
        let settings = ControllerSettings(legacyPlist: [
            "slipModeFlashing": "0",
            "slipModeButtonSetting": "1",
            "faderStartOptionIndex": "3",
            "jogRingColorIndex": "2",
            "timeDisplayFormat": "0",
            "virtualDeckModeCheckbutton": "0",
            "recOutIndex": "1",
            "softwarePulldownIndex": "0",
        ])
        XCTAssertEqual(settings.slipModeFlashing, .disable)
        XCTAssertEqual(settings.slipButtonLED, .blink)
        XCTAssertEqual(settings.faderStartSync, .on)
        XCTAssertEqual(settings.jogRingColor, .mode3)
        XCTAssertEqual(settings.timeMode, .elapsed)
        XCTAssertEqual(settings.virtualDeckMode, .off)
        XCTAssertEqual(settings.recOut, .withoutMic)
        XCTAssertEqual(settings.software, .rekordbox)
    }

    func testLegacyOutOfRangeFallsBackToDefaults() {
        let settings = ControllerSettings(legacyPlist: ["jogRingColorIndex": "7", "faderStartOptionIndex": "1"])
        XCTAssertEqual(settings.jogRingColor, .mode1)
        XCTAssertEqual(settings.faderStartSync, .off)
    }

    func testFirmwareFormatting() {
        XCTAssertEqual(USBControlClient.formatFirmware([0x01, 0x05]), "1.05")
        XCTAssertEqual(USBControlClient.formatFirmware([0x02, 0x1A]), "2.1a")
    }
}

final class LogoLayoutTests: XCTestCase {
    func testFillCoversCanvasAndCentres() {
        let rect = LogoImageEncoder.fillRect(imageWidth: 480, imageHeight: 240, side: 240, zoom: 1, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: -120, y: 0, width: 480, height: 240))
    }

    func testFillOffsetAlignsEdges() {
        // offset.x = 1 moves the image right until its left edge meets the canvas edge.
        let right = LogoImageEncoder.fillRect(imageWidth: 480, imageHeight: 240, side: 240, zoom: 1, offset: CGPoint(x: 1, y: 0))
        XCTAssertEqual(right.minX, 0)
        let left = LogoImageEncoder.fillRect(imageWidth: 480, imageHeight: 240, side: 240, zoom: 1, offset: CGPoint(x: -1, y: 0))
        XCTAssertEqual(left.maxX, 240)
        // Screen-down (positive y) lowers the image, i.e. smaller CoreGraphics y.
        let down = LogoImageEncoder.fillRect(imageWidth: 240, imageHeight: 480, side: 240, zoom: 1, offset: CGPoint(x: 0, y: 1))
        XCTAssertEqual(down.maxY, 240)
    }

    func testFillZoom() {
        let rect = LogoImageEncoder.fillRect(imageWidth: 240, imageHeight: 240, side: 240, zoom: 2, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: -120, y: -120, width: 480, height: 480))
    }

    func testLayoutClamps() {
        var layout = LogoLayout(mode: .fill, zoom: 10, offset: CGPoint(x: 3, y: -3))
        XCTAssertEqual(layout.zoom, LogoLayout.maxZoom)
        XCTAssertEqual(layout.offset, CGPoint(x: 1, y: -1))
        layout.zoom = 0.2
        XCTAssertEqual(layout.zoom, 1)
    }

    func testDragConvertsToOffset() {
        let layout = LogoLayout(mode: .fill)
        // 480×240 at zoom 1 overflows by 240pt horizontally; dragging 120pt is half of it → 1.0.
        let offset = layout.offset(afterDragging: CGSize(width: 120, height: 50), from: .zero,
                                   imageWidth: 480, imageHeight: 240, canvasSide: 240)
        XCTAssertEqual(offset.x, 1, accuracy: 0.0001)
        XCTAssertEqual(offset.y, 0, "No vertical overflow, so vertical drag is ignored")
    }

    func testFillLeavesNoLetterbox() throws {
        let context = CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        let source = context.makeImage()!

        func topLeftBrightness(_ layout: LogoLayout) -> UInt8 {
            let image = LogoImageEncoder.render(source, layout: layout)!
            let data = image.dataProvider!.data! as Data
            return data[0]
        }
        XCTAssertEqual(topLeftBrightness(.fit), 0, "Fit letterboxes with black")
        XCTAssertGreaterThan(topLeftBrightness(LogoLayout(mode: .fill)), 200, "Fill covers the canvas")
    }
}
