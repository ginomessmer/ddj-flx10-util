import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts an arbitrary image file into the logo payload the controller expects.
///
/// Observed in the original tool: the image is aspect-fit and centred on a black 240×240 canvas,
/// then encoded with JUCE's JPEG writer at quality 1.0. Source files are limited per format
/// (bmp 512 MiB, jpg/jpeg 100 MiB, png 64 MiB, gif 7 MiB) and the JPEG must fit in 0x2A400 bytes.
public enum LogoImageEncoder {
    public enum EncodingError: LocalizedError, Equatable {
        case unsupportedFormat
        case sourceTooLarge
        case unreadable
        case payloadTooLarge

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Unsupported file format. Supported formats: BMP, JPG, PNG, GIF."
            case .sourceTooLarge: return "File size is too large."
            case .unreadable: return "Failed to open the file."
            case .payloadTooLarge: return "The converted image is too large for the controller."
            }
        }
    }

    public struct Result {
        /// The 240×240 image as it will appear on the jog display.
        public let preview: CGImage
        public let jpegData: Data
    }

    /// Maximum source file size per lowercase extension.
    public static let sourceLimits: [String: Int] = [
        "bmp": 512 * 1024 * 1024,
        "jpg": 100 * 1024 * 1024,
        "jpeg": 100 * 1024 * 1024,
        "png": 64 * 1024 * 1024,
        "gif": 7 * 1024 * 1024,
    ]

    public static var supportedExtensions: [String] { sourceLimits.keys.sorted() }

    public static func isSupported(_ url: URL) -> Bool {
        sourceLimits[url.pathExtension.lowercased()] != nil
    }

    public static func encode(fileAt url: URL) throws -> Result {
        guard let limit = sourceLimits[url.pathExtension.lowercased()] else { throw EncodingError.unsupportedFormat }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw EncodingError.sourceTooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = orientedImage(from: source) else { throw EncodingError.unreadable }
        return try encode(image: image)
    }

    public static func encode(image: CGImage) throws -> Result {
        guard let canvas = render(image) else { throw EncodingError.unreadable }
        // Design choice: the original gives up when the quality-1.0 JPEG exceeds the buffer; we step
        // the quality down instead. A 240×240 JPEG at 1.0 is normally far below the limit.
        for quality in [1.0, 0.95, 0.9, 0.8, 0.7] {
            if let data = jpegData(canvas, quality: quality), data.count <= LogoProtocol.maxPayloadLength {
                return Result(preview: canvas, jpegData: data)
            }
        }
        throw EncodingError.payloadTooLarge
    }

    /// Decodes the first frame and applies its EXIF/TIFF orientation.
    static func orientedImage(from source: CGImageSource) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Aspect-fits `image` onto a black square canvas, centred, matching the original's
    /// truncating integer arithmetic.
    static func render(_ image: CGImage) -> CGImage? {
        let side = LogoProtocol.displaySize
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let fit = fitRect(imageWidth: image.width, imageHeight: image.height, side: side)
        context.interpolationQuality = .high
        // CoreGraphics' origin is bottom-left; the centred rect is symmetric so y needs no flip.
        context.draw(image, in: fit)
        return context.makeImage()
    }

    static func fitRect(imageWidth: Int, imageHeight: Int, side: Int) -> CGRect {
        guard imageWidth > 0, imageHeight > 0 else { return .zero }
        let scaleX = Float(side) / Float(imageWidth)
        let scaleY = Float(side) / Float(imageHeight)
        if scaleY > scaleX {
            let height = Int(scaleX * Float(imageHeight))
            return CGRect(x: 0, y: (side - height) / 2, width: side, height: height)
        } else {
            let width = Int(scaleY * Float(imageWidth))
            return CGRect(x: (side - width) / 2, y: 0, width: width, height: side)
        }
    }

    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
