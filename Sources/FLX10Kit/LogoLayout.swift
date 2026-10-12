import CoreGraphics

/// How a source image is placed on the 240×240 logo canvas.
public struct LogoLayout: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        /// Whole image visible, letterboxed with black (the original tool's behaviour).
        case fit
        /// Canvas covered, overflow cropped.
        case fill
    }

    public static let maxZoom: Double = 4
    public static let fit = LogoLayout(mode: .fit)

    public var mode: Mode
    /// Extra magnification in fill mode, 1...maxZoom.
    public var zoom: Double {
        didSet { zoom = min(max(zoom, 1), Self.maxZoom) }
    }
    /// Crop position in fill mode, -1...1 per axis (screen orientation, 0 = centred).
    public var offset: CGPoint {
        didSet { offset = CGPoint(x: min(max(offset.x, -1), 1), y: min(max(offset.y, -1), 1)) }
    }

    public init(mode: Mode, zoom: Double = 1, offset: CGPoint = .zero) {
        self.mode = mode
        self.zoom = min(max(zoom, 1), Self.maxZoom)
        self.offset = CGPoint(x: min(max(offset.x, -1), 1), y: min(max(offset.y, -1), 1))
    }

    /// Whether the crop can move along each axis for an image of this size (fill mode only).
    public static func canPan(imageWidth: Int, imageHeight: Int, zoom: Double) -> (x: Bool, y: Bool) {
        guard imageWidth > 0, imageHeight > 0 else { return (false, false) }
        let side = Double(LogoProtocol.displaySize)
        let scale = max(side / Double(imageWidth), side / Double(imageHeight)) * zoom
        return (Double(imageWidth) * scale > side + 0.5, Double(imageHeight) * scale > side + 0.5)
    }

    /// Converts a drag in canvas points into an offset change for an image of this size.
    public func offset(afterDragging translation: CGSize, from start: CGPoint, imageWidth: Int, imageHeight: Int, canvasSide: Double) -> CGPoint {
        guard imageWidth > 0, imageHeight > 0, canvasSide > 0 else { return start }
        let scale = max(canvasSide / Double(imageWidth), canvasSide / Double(imageHeight)) * zoom
        let overflowX = Double(imageWidth) * scale - canvasSide
        let overflowY = Double(imageHeight) * scale - canvasSide
        let dx = overflowX > 0.5 ? translation.width / (overflowX / 2) : 0
        let dy = overflowY > 0.5 ? translation.height / (overflowY / 2) : 0
        return CGPoint(x: start.x + dx, y: start.y + dy)
    }
}
